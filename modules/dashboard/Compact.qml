pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.images
import qs.services

Item {
    id: root

    property bool active: true

    readonly property var player: Players.active
    readonly property bool recording: Recorder.running
    readonly property bool media: !recording && !!player
    readonly property bool playing: media && (player?.isPlaying ?? false)
    readonly property string title: visibleText(player?.trackTitle) || visibleText(Players.getIdentity(player)) || Tr.tr("Unknown title")
    readonly property real position: player?.position ?? 0
    readonly property real length: player?.length ?? 0
    readonly property bool hasProgress: media && (player?.positionSupported ?? false) && Number.isFinite(length) && length > 0
    readonly property real progress: hasProgress ? Math.max(0, Math.min(1, position / length)) : 0
    readonly property real mediaWidth: 348
    readonly property real controlWidth: 32
    readonly property bool hovered: hover.hovered
    readonly property bool controlsVisible: media && (!playing || hovered)
    readonly property int hoveredControl: controlsVisible && hover.hovered && hover.point.position.x >= width - controlWidth ? 1 : 0
    readonly property bool marqueeOverflow: titleViewport.width > 0 && titleText.implicitWidth > titleViewport.width + 1
    readonly property real marqueeDistance: Math.max(0, titleText.implicitWidth - titleViewport.width)
    property int pressedControl: 0

    function visibleText(value: string): string {
        if (!value)
            return "";
        return value.replace(/[\s\u00A0\u034F\u1680\u2000-\u200F\u2028-\u202F\u205F-\u206F\u2800\u3164\uFEFF\uFFA0]+/g, " ").trim();
    }

    function formatElapsed(seconds: real): string {
        const total = Math.max(0, Math.floor(seconds));
        const hours = Math.floor(total / 3600);
        const minutes = Math.floor(total % 3600 / 60);
        const remainder = (total % 60).toString().padStart(2, "0");
        return hours > 0 ? `${hours}:${minutes.toString().padStart(2, "0")}:${remainder}` : `${minutes}:${remainder}`;
    }

    function resetMarquee(): void {
        if (!titleText)
            return;
        titleText.x = 0;
        if (marqueeOverflow && active && marquee)
            marquee.restart();
    }

    function primaryAction(): void {
        if (!player)
            return;
        if (playing)
            player.pause();
        else
            player.play();
    }

    implicitWidth: media ? mediaWidth : row.implicitWidth
    implicitHeight: Math.max(24, row.implicitHeight)
    enabled: active

    onActiveChanged: {
        if (active && titleText) {
            titleText.x = 0;
            if (marqueeOverflow && marquee)
                marquee.restart();
        }
    }
    onMarqueeOverflowChanged: {
        if (!marqueeOverflow) {
            if (marquee)
                marquee.stop();
            if (titleText)
                titleText.x = 0;
        }
    }

    RowLayout {
        id: row

        anchors.fill: parent
        spacing: Tokens.spacing.small

        ClipRect {
            visible: root.media
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: 24
            implicitHeight: 24
            radius: Tokens.rounding.small
            color: Colours.palette.m3surfaceContainerHighest

            FadeImage {
                id: art

                anchors.fill: parent
                source: root.media ? Players.getArtUrl(root.player) : ""
            }

            MaterialIcon {
                anchors.centerIn: parent
                visible: art.status !== Image.Ready
                text: "album"
                color: Colours.palette.m3primary
                fontStyle: Tokens.font.icon.small
            }
        }

        ColumnLayout {
            visible: root.media
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.alignment: Qt.AlignVCenter
            spacing: 2

            Item {
                id: titleViewport

                Layout.fillWidth: true
                Layout.minimumWidth: 0
                implicitHeight: titleText.implicitHeight
                clip: true

                onWidthChanged: root.resetMarquee()

                StyledText {
                    id: titleText

                    width: implicitWidth
                    text: root.title
                    font: Tokens.font.body.small
                    color: Colours.palette.m3onSurface

                    onImplicitWidthChanged: root.resetMarquee()
                }
            }

            StyledRect {
                visible: root.hasProgress
                Layout.fillWidth: true
                Layout.preferredHeight: 2
                radius: height / 2
                color: Qt.alpha(Colours.palette.m3onSurface, 0.14)

                StyledRect {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width * root.progress
                    height: parent.height
                    radius: height / 2
                    color: Colours.palette.m3primary

                    Behavior on width {
                        Anim {
                            type: Anim.FastEffects
                        }
                    }
                }

                StyledRect {
                    anchors.verticalCenter: parent.verticalCenter
                    x: Math.max(0, Math.min(parent.width - width, parent.width * root.progress - width / 2))
                    width: 4
                    height: 4
                    radius: height / 2
                    color: Colours.palette.m3primary

                    Behavior on x {
                        Anim {
                            type: Anim.FastEffects
                        }
                    }
                }
            }
        }

        Item {
            visible: root.media
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: root.controlWidth
            implicitHeight: 24

            AudioWave {
                anchors.fill: parent
                running: root.active && root.playing && !root.controlsVisible
                opacity: root.controlsVisible ? 0 : 1
                scale: root.controlsVisible ? 0.82 : 1
                visible: opacity > 0

                Behavior on opacity {
                    Anim {
                        type: Anim.FastEffects
                    }
                }

                Behavior on scale {
                    Anim {
                        type: Anim.FastSpatial
                    }
                }
            }

            ControlButton {
                anchors.centerIn: parent
                icon: root.playing ? "pause" : "play_arrow"
                control: 1
                tint: Colours.palette.m3primary
                opacity: root.controlsVisible ? 1 : 0
                scale: root.controlsVisible ? 1 : 0.82
                visible: opacity > 0

                Behavior on opacity {
                    Anim {
                        type: Anim.FastEffects
                    }
                }

                Behavior on scale {
                    Anim {
                        type: Anim.FastSpatial
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                enabled: root.controlsVisible
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.PointingHandCursor

                onPressed: root.pressedControl = 1
                onReleased: root.pressedControl = 0
                onCanceled: root.pressedControl = 0
                onClicked: root.primaryAction()
            }
        }

        StyledRect {
            visible: root.recording
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: 7
            implicitHeight: 7
            radius: Tokens.rounding.full
            color: Recorder.paused ? Colours.palette.m3tertiary : Colours.palette.m3error
        }

        StyledText {
            visible: root.recording
            Layout.alignment: Qt.AlignVCenter
            text: Recorder.paused ? Tr.tr("PAUSED") : Tr.tr("REC")
            color: Recorder.paused ? Colours.palette.m3tertiary : Colours.palette.m3error
            font: Tokens.font.label.small
        }

        StyledText {
            visible: root.recording
            Layout.alignment: Qt.AlignVCenter
            text: root.formatElapsed(Recorder.elapsed)
            font: Tokens.font.mono.small
        }

        StyledRect {
            visible: !root.media && !root.recording
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: 6
            implicitHeight: 6
            radius: Tokens.rounding.full
            color: Colours.palette.m3primary
        }

        StyledText {
            visible: !root.media && !root.recording
            Layout.alignment: Qt.AlignVCenter
            text: Time.timeStr
            color: Colours.palette.m3onSurface
            font: Tokens.font.body.builders.small.weight(Font.DemiBold).build()
        }
    }

    SequentialAnimation {
        id: marquee

        loops: Animation.Infinite
        running: root.active && root.marqueeOverflow

        PauseAnimation {
            duration: 1500
        }

        NumberAnimation {
            target: titleText
            property: "x"
            from: 0
            to: -root.marqueeDistance
            duration: Math.max(2500, root.marqueeDistance * 20)
            easing.type: Easing.Linear
        }

        PauseAnimation {
            duration: 1400
        }

        PropertyAction {
            target: titleText
            property: "x"
            value: 0
        }
    }

    Timer {
        interval: GlobalConfig.dashboard.mediaUpdateInterval
        repeat: true
        running: root.active && root.media && root.playing && (root.player?.positionSupported ?? false)
        triggeredOnStart: true

        onTriggered: root.player?.positionChanged()
    }

    HoverHandler {
        id: hover

        enabled: root.active
    }

    component ControlButton: Item {
        id: button

        required property string icon
        required property int control
        property color tint: Colours.palette.m3onSurface

        readonly property bool hovered: root.hoveredControl === control
        readonly property bool pressed: root.pressedControl === control

        implicitWidth: 24
        implicitHeight: 24

        StyledRect {
            anchors.fill: parent
            radius: Tokens.rounding.full
            color: Colours.palette.m3onSurface
            opacity: button.hovered || button.pressed ? (button.pressed ? 0.16 : 0.08) : 0

            Behavior on opacity {
                Anim {
                    type: Anim.FastEffects
                }
            }
        }

        MaterialIcon {
            anchors.centerIn: parent
            text: button.icon
            color: button.tint
            fontStyle: Tokens.font.icon.small
            scale: button.pressed ? 0.86 : 1

            Behavior on scale {
                Anim {
                    type: Anim.FastSpatial
                }
            }
        }
    }
}
