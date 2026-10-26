pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.filedialog
import qs.utils

Item {
    id: root

    required property ScreenState screenState
    property bool fullscreen: false

    readonly property FileDialog facePicker: FileDialog {
        title: Tr.tr("Select a profile picture")
        filterLabel: Tr.tr("Image files")
        filters: Images.validImageExtensions
        onAccepted: path => {
            if (CUtils.copyFile(Qt.resolvedUrl(path), Qt.resolvedUrl(`${Paths.home}/.face`)))
                // TRANSLATORS: %1 = a file path
                Quickshell.execDetached(["notify-send", "-a", "caelestia-shell", "-u", "low", "-h", `STRING:image-path:${path}`, Tr.tr("Profile picture changed"), Tr.tr("Profile picture changed to %1").arg(Paths.shortenHome(path))]);
            else
                Quickshell.execDetached(["notify-send", "-a", "caelestia-shell", "-u", "critical", Tr.tr("Unable to change profile picture"), Tr.tr("Failed to change profile picture to %1").arg(Paths.shortenHome(path))]);
        }
    }

    readonly property bool enabled: Config.dashboard.enabled
    readonly property bool expanded: screenState.dashboard && enabled
    readonly property real nonAnimHeight: (expandedContent.item as Content)?.nonAnimHeight ?? 0
    readonly property real compactHeight: Math.max(36, compact.implicitHeight + Tokens.padding.extraSmall * 2)
    readonly property real compactWidth: Math.max(96, compact.implicitWidth + Tokens.padding.medium * 2)
    readonly property real expandedWidth: (expandedContent.item as Content)?.nonAnimWidth || expandedWidthCache || 1064
    readonly property real expandedHeight: (expandedContent.item as Content)?.nonAnimHeight || expandedHeightCache || 420
    property real expandedWidthCache: 0
    property real expandedHeightCache: 0
    readonly property real targetWidth: expanded ? expandedWidth : compactWidth
    readonly property real targetHeight: expanded ? expandedHeight : compactHeight

    property real morph: expanded ? 1 : 0
    property real animatedWidth: targetWidth
    property real animatedHeight: targetHeight

    implicitWidth: animatedWidth
    implicitHeight: animatedHeight
    visible: enabled && !fullscreen
    clip: true

    Behavior on morph {
        Anim {}
    }

    Behavior on animatedWidth {
        Anim {}
    }

    Behavior on animatedHeight {
        Anim {}
    }

    Connections {
        function onNonAnimWidthChanged(): void {
            root.expandedWidthCache = target.nonAnimWidth;
        }

        function onNonAnimHeightChanged(): void {
            root.expandedHeightCache = target.nonAnimHeight;
        }

        target: expandedContent.item
    }

    Item {
        id: compactContainer

        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width
        height: root.compactHeight

        opacity: 1 - root.morph
        scale: 1 - root.morph * 0.06
        visible: opacity > 0

        Compact {
            id: compact

            anchors.centerIn: parent
            active: !root.expanded

            onExpandRequested: root.screenState.dashboard = true
        }
    }

    Item {
        id: expandedContainer

        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.expandedWidth
        height: root.expandedHeight

        opacity: root.morph
        visible: opacity > 0
        enabled: root.expanded

        Behavior on width {
            Anim {}
        }

        Behavior on height {
            Anim {}
        }

        Loader {
            id: expandedContent

            anchors.fill: parent
            active: root.expanded || expandedContainer.opacity > 0

            sourceComponent: Content {
                screenState: root.screenState
                facePicker: root.facePicker
            }
        }
    }
}
