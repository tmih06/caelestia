pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.filedialog
import qs.services
import qs.utils

Item {
    id: root

    required property ScreenState screenState
    property bool fullscreen: false
    property Item compactDock

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
    readonly property bool mediaDock: compactDock ? compactDock.dockId === "media" : false
    property bool morphTargetsReady: false
    property int morphAttempts: 0
    property Item coverTargetItem
    property Item titleTargetItem
    property Item timelineTargetItem
    property Item waveTargetItem
    property rect artTargetRect
    property rect titleTargetRect
    property rect timelineTargetRect
    property rect waveTargetRect
    readonly property real nonAnimHeight: (expandedContent.item as Content)?.nonAnimHeight ?? 0
    readonly property real compactHeight: compactDock ? Math.max(36, compactDock.implicitHeight + Tokens.padding.extraSmall * 2) : 36
    readonly property real compactWidth: compactDock ? Math.max(96, compactDock.implicitWidth + Tokens.padding.medium * 2) : 96
    readonly property real expandedWidth: (expandedContent.item as Content)?.nonAnimWidth || expandedWidthCache || 1064
    readonly property real expandedHeight: (expandedContent.item as Content)?.nonAnimHeight || expandedHeightCache || 420
    property real expandedWidthCache: 0
    property real expandedHeightCache: 0
    readonly property real targetWidth: expanded ? expandedWidth : compactWidth
    readonly property real targetHeight: expanded ? expandedHeight : compactHeight

    property real morph: expanded ? 1 : 0
    property real animatedWidth: targetWidth
    property real animatedHeight: targetHeight

    function lerp(from: real, to: real, t: real): real {
        return from + (to - from) * t;
    }

    function itemRect(item: Item): rect {
        if (!item)
            return Qt.rect(0, 0, 0, 0);
        const pos = item.mapToItem(root, 0, 0);
        return Qt.rect(pos.x, pos.y, item.width, item.height);
    }

    function selectDockTab(): void {
        if (!compactDock)
            return;
        const content = expandedContent.item;
        if (!content || !content.dashboardTabs)
            return;
        const index = content.dashboardTabs.findIndex(tab => tab.id === compactDock.targetTab);
        if (index >= 0 && root.screenState.dashboardTab !== index)
            root.screenState.dashboardTab = index;
    }

    function resetMorphTargets(): void {
        coverTargetItem = null;
        titleTargetItem = null;
        timelineTargetItem = null;
        waveTargetItem = null;
        morphAttempts = 0;
        morphTargetsReady = artTargetRect.width > 0 && titleTargetRect.width > 0 && waveTargetRect.width > 0;
    }


    function updateMorph(): void {
        if (!compactDock || !mediaDock || !compactDock.media)
            return;
        const content = expandedContent.item;
        if (!content)
            return;

        if (!coverTargetItem)
            coverTargetItem = CUtils.findChild(content, "dockMorphCover");
        if (!titleTargetItem)
            titleTargetItem = CUtils.findChild(content, "dockMorphTitle");
        if (!timelineTargetItem)
            timelineTargetItem = CUtils.findChild(content, "dockMorphTimeline");
        if (!waveTargetItem)
            waveTargetItem = CUtils.findChild(content, "dockMorphWave");

        if (!coverTargetItem || !titleTargetItem || !waveTargetItem)
            return;
        if (coverTargetItem.width <= 0 || titleTargetItem.width <= 0 || waveTargetItem.width <= 0)
            return;

        artTargetRect = itemRect(coverTargetItem);
        titleTargetRect = itemRect(titleTargetItem);
        timelineTargetRect = itemRect(timelineTargetItem);
        waveTargetRect = itemRect(waveTargetItem);
        morphTargetsReady = true;
    }

    implicitWidth: animatedWidth
    implicitHeight: animatedHeight
    visible: enabled && !fullscreen
    clip: true

    Component.onCompleted: compactDock = compact

    onExpandedChanged: {
        if (expanded) {
            resetMorphTargets();
            selectDockTab();
            Qt.callLater(updateMorph);
        }
    }

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
            active: root.expanded || root.morph > 0.01

            onItemChanged: {
                root.resetMorphTargets();
                if (root.expanded) {
                    root.selectDockTab();
                    Qt.callLater(root.updateMorph);
                }
            }

            sourceComponent: Content {
                screenState: root.screenState
                facePicker: root.facePicker
                dockMorph: root.mediaDock ? root.morph : 1
            }
        }
    }

    Timer {
        interval: 80
        repeat: true
        running: root.expanded && root.mediaDock && !root.morphTargetsReady && root.morphAttempts < 50

        onTriggered: {
            root.morphAttempts++;
            root.updateMorph();
        }
    }

    MediaDock {
        anchors.fill: parent
        compactWidth: root.compactWidth
        compactHeight: root.compactHeight
        active: !root.expanded
        morph: root.morph
        targetReady: root.morphTargetsReady
        artTargetRect: root.artTargetRect
        titleTargetRect: root.titleTargetRect
        timelineTargetRect: root.timelineTargetRect
        waveTargetRect: root.waveTargetRect
        opacity: root.mediaDock ? (root.morph < 0.85 ? 1 : Math.max(0, (1 - root.morph) / 0.15)) : 0
        visible: opacity > 0
    }
}
