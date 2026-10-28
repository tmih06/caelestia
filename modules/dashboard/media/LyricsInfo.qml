import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia
import Caelestia.Blobs
import Caelestia.Config
import Caelestia.I18n
import Caelestia.Services
import qs.components
import qs.modules.drawers
import qs.services

Item {
    id: root

    property bool open
    property bool pageActive: true
    readonly property real padding: Tokens.padding.large

    // The overlay is kept at 1x1 while closed so its content is still laid out
    // (and can be measured), without intercepting input or appearing at a
    // stale mapped position while the drawer animates.
    property bool overlayActive: false

    // Defer the visual expansion until the content has finished its first
    // layout pass. Without this the blob expands using the placeholder height
    // and then has to grow again when the lyric details are measured.
    property bool expanded: false
    property bool contentSettled: false

    implicitWidth: btn.implicitWidth * 0.9
    implicitHeight: btn.implicitHeight * 0.9

    Component.onCompleted: settleTimer.restart()

    onPageActiveChanged: {
        if (!pageActive) {
            open = false;
            expanded = false;
            settleTimer.stop();
            maxWaitTimer.stop();
            closeTimer.stop();
            overlayActive = false;
        }
    }

    onOpenChanged: {
        if (open) {
            if (contentSettled) {
                expanded = true;
            } else {
                settleTimer.restart();
                maxWaitTimer.restart();
            }
        } else {
            expanded = false;
            settleTimer.stop();
            maxWaitTimer.stop();
            if (overlayActive)
                closeTimer.restart();
        }
    }

    onExpandedChanged: {
        if (expanded) {
            closeTimer.stop();
            overlayActive = true;
        } else if (overlayActive) {
            closeTimer.restart();
        }
    }

    Timer {
        id: closeTimer

        interval: root.Tokens.anim.durations.expressiveDefaultSpatial + 50

        onTriggered: root.overlayActive = false
    }

    Timer {
        id: settleTimer

        interval: 300

        onTriggered: {
            root.contentSettled = true;
            if (root.open && !root.expanded)
                root.expanded = true;
        }
    }

    Timer {
        id: maxWaitTimer

        interval: 1000

        onTriggered: {
            if (root.open)
                root.expanded = true;
        }
    }

    Connections {
        function onImplicitHeightChanged(): void {
            if (!root.expanded) {
                root.contentSettled = false;
                settleTimer.restart();
            }
        }

        target: layout
    }

    Connections {
        function onImplicitHeightChanged(): void {
            if (!root.expanded) {
                root.contentSettled = false;
                settleTimer.restart();
            }
        }

        target: placeholder
    }

    BlobGroup {
        id: inlineGroup

        color: Colours.palette.m3surfaceContainerHighest
        smoothing: root.Tokens.rounding.medium
        cornerFill: false

        Behavior on color {
            CAnim {}
        }
    }

    BlobRect {
        id: inlineBtnRect

        anchors.fill: parent
        anchors.margins: !btn.pressed && btn.containsMouse ? -Tokens.padding.extraSmall : 0
        group: inlineGroup
        radius: Tokens.rounding.medium
        visible: !root.expanded

        Behavior on anchors.margins {
            Anim {}
        }
    }

    Item {
        id: overlay

        parent: {
            const win = root.QsWindow.window;
            const contentWin = win as ContentWindow;
            return contentWin ? contentWin.interactionWrapper : (win?.contentItem ?? null);
        }
        width: root.overlayActive && parent ? parent.width : 1
        height: root.overlayActive && parent ? parent.height : 1
        visible: root.pageActive
        enabled: root.overlayActive
        opacity: root.overlayActive ? 1 : 0
        z: 1000

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }

        TransformWatcher {
            id: watcher

            a: overlay.parent
            b: root
        }

        Item {
            id: trigger

            x: {
                CUtils.dependency(watcher.transform);
                return root.mapToItem(overlay, 0, 0).x;
            }
            y: {
                CUtils.dependency(watcher.transform);
                return root.mapToItem(overlay, 0, 0).y;
            }
            width: root.width
            height: root.height

            BlobGroup {
                id: blobGroup

                color: Colours.palette.m3surfaceContainerHighest
                smoothing: root.Tokens.rounding.medium
                cornerFill: false

                Behavior on color {
                    CAnim {}
                }
            }

            BlobRect {
                id: btnRect

                anchors.fill: parent
                anchors.margins: !btn.pressed && btn.containsMouse ? -Tokens.padding.extraSmall : 0
                group: blobGroup
                radius: Tokens.rounding.medium

                Behavior on anchors.margins {
                    Anim {}
                }
            }

            BlobRect {
                id: rect

                anchors.right: parent.right
                anchors.top: parent.top

                implicitWidth: parent.width
                implicitHeight: parent.height

                group: blobGroup
                radius: Tokens.rounding.medium
                deformScale: 0.00001

                // Reserve space for the loaded layout even while a lookup is
                // in flight, so finishing the lookup cannot resize the panel.
                readonly property real expandedContentHeight: Math.max(layout.implicitHeight, placeholder.implicitHeight)

                states: State {
                    name: "open"
                    when: root.expanded

                    PropertyChanges {
                        rect.anchors.rightMargin: root.width - root.Tokens.spacing.small
                        rect.anchors.topMargin: -root.Tokens.padding.medium
                        rect.implicitWidth: root.Tokens.sizes.dashboard.mediaSectionWidth + root.padding * 2
                        rect.implicitHeight: rect.expandedContentHeight + root.padding * 2
                        content.opacity: 1
                    }
                }

                transitions: Transition {
                    Anim {
                        properties: "rightMargin,implicitWidth"
                    }
                    Anim {
                        properties: "topMargin,implicitHeight"
                        easing: root.Tokens.anim.expressiveFastSpatial
                    }
                    Anim {
                        property: "opacity"
                        type: Anim.DefaultEffects
                    }
                }

                Behavior on implicitWidth {
                    Anim {}
                }

                Behavior on implicitHeight {
                    Anim {}
                }

                Item {
                    id: content

                    anchors.fill: parent
                    clip: true
                    opacity: 0
                    state: Lyrics.loading || !Lyrics.hasLyrics ? "" : "hasLyrics"

                    states: State {
                        name: "hasLyrics"

                        PropertyChanges {
                            layout.opacity: 1
                            placeholder.opacity: 0
                        }
                    }

                    transitions: [
                        Transition {
                            from: "hasLyrics"

                            SequentialAnimation {
                                Anim {
                                    target: layout
                                    property: "opacity"
                                    type: Anim.FastEffects
                                }
                                Anim {
                                    target: placeholder
                                    property: "opacity"
                                    type: Anim.DefaultEffects
                                }
                            }
                        },
                        Transition {
                            to: "hasLyrics"

                            SequentialAnimation {
                                Anim {
                                    target: placeholder
                                    property: "opacity"
                                    type: Anim.FastEffects
                                }
                                Anim {
                                    target: layout
                                    property: "opacity"
                                    type: Anim.DefaultEffects
                                }
                            }
                        }
                    ]

                    ColumnLayout {
                        id: layout

                        anchors.centerIn: parent
                        width: Tokens.sizes.dashboard.mediaSectionWidth
                        spacing: Tokens.spacing.extraSmall
                        opacity: 0

                        LyricsLookupStatus {
                            Layout.fillWidth: true
                            // Keep the lookup history loaded while closed so the
                            // first open already has its final height.
                            active: true
                        }

                        StyledText {
                            Layout.fillWidth: true
                            // TRANSLATORS: %1/%2/%3 = matched track title, artist and album
                            text: Tr.tr("Selected candidate: %1 | %2 | %3").arg(Lyrics.selectedCandidate.title).arg(Lyrics.selectedCandidate.artist).arg(Lyrics.selectedCandidate.album)
                            color: Colours.palette.m3onSurfaceVariant
                            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                            animate: true
                        }

                        StyledText {
                            // TRANSLATORS: %1 = lyric timing offset; ms is the millisecond unit, leave untranslated
                            text: Tr.tr("Offset: %1 ms").arg(Lyrics.offset)
                            color: Colours.palette.m3onSurfaceVariant
                            animate: true
                        }
                    }

                    LyricsLookupStatus {
                        id: placeholder

                        anchors.centerIn: parent
                        width: Tokens.sizes.dashboard.mediaSectionWidth
                        active: true
                    }
                }
            }

            MaterialIcon {
                anchors.centerIn: parent
                text: "more_vert"
                fontStyle: Tokens.font.icon.medium
            }
        }
    }

    MouseArea {
        id: btn

        anchors.centerIn: parent
        implicitWidth: implicitHeight
        implicitHeight: icon.implicitHeight + Tokens.padding.extraSmall * 2
        cursorShape: Qt.PointingHandCursor
        hoverEnabled: true
        onClicked: root.open = !root.open

        MaterialIcon {
            id: icon

            anchors.centerIn: parent
            text: "more_vert"
            fontStyle: Tokens.font.icon.medium
            visible: !root.expanded
        }
    }
}
