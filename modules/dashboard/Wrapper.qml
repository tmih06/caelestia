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
    readonly property bool mediaDock: enabled && compactDock ? compactDock.dockId === "media" : false
    readonly property bool mediaSelected: (expandedContent.item as Content)?.dashboardTabs[screenState.dashboardTab]?.id === "media"
    property bool morphTargetsReady: false
    property int morphAttempts: 0
    property Item coverTargetItem
    property Item titleTargetItem
    property Item channelTargetItem
    property Item albumTargetItem
    property Item timelineTargetItem
    property Item positionLabelTargetItem
    property Item durationLabelTargetItem
    property Item waveTargetItem
    property rect artTargetRect
    property rect titleTargetRect
    property rect channelTargetRect
    property rect albumTargetRect
    property rect timelineTargetRect
    property rect positionLabelTargetRect
    property rect durationLabelTargetRect
    property rect waveTargetRect
    readonly property real nonAnimHeight: (expandedContent.item as Content)?.nonAnimHeight ?? 0
    readonly property real compactHeight: compactDock ? Math.max(36, compactDock.implicitHeight + Tokens.padding.extraSmall * 2) : 36
    readonly property real compactWidth: compactDock ? Math.max(96, compactDock.implicitWidth + Tokens.padding.medium * 2) : 96
    readonly property real expandedWidth: (expandedContent.item as Content)?.nonAnimWidth || expandedWidthCache || 1064
    readonly property real expandedHeight: (expandedContent.item as Content)?.nonAnimHeight || expandedHeightCache || 420
    property real expandedWidthCache: 0
    property real expandedHeightCache: 0

    property real morph: expanded ? 1 : 0
    property real pageWidth: expandedWidth
    property real pageHeight: expandedHeight

    function targetRect(item: Item): rect {
        if (!item)
            return Qt.rect(0, 0, 0, 0);
        return expandedContent.item.mediaTargetRect(item);
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
        channelTargetItem = null;
        albumTargetItem = null;
        timelineTargetItem = null;
        positionLabelTargetItem = null;
        durationLabelTargetItem = null;
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
        if (!expanded)
            selectDockTab();

        if (!coverTargetItem)
            coverTargetItem = CUtils.findChild(content, "dockMorphCover");
        if (!titleTargetItem)
            titleTargetItem = CUtils.findChild(content, "dockMorphTitle");
        if (!channelTargetItem)
            channelTargetItem = CUtils.findChild(content, "dockMorphChannel");
        if (!albumTargetItem)
            albumTargetItem = CUtils.findChild(content, "dockMorphAlbum");
        if (!timelineTargetItem)
            timelineTargetItem = CUtils.findChild(content, "dockMorphTimeline");
        if (!positionLabelTargetItem)
            positionLabelTargetItem = CUtils.findChild(content, "dockMorphPositionLabel");
        if (!durationLabelTargetItem)
            durationLabelTargetItem = CUtils.findChild(content, "dockMorphDurationLabel");
        if (!waveTargetItem)
            waveTargetItem = CUtils.findChild(content, "dockMorphWave");

        if (!coverTargetItem || !titleTargetItem || !channelTargetItem || !albumTargetItem || !timelineTargetItem || !waveTargetItem || !positionLabelTargetItem || !durationLabelTargetItem)
            return;
        if (coverTargetItem.width <= 0 || titleTargetItem.width <= 0 || channelTargetItem.width <= 0 || albumTargetItem.width <= 0 || timelineTargetItem.width <= 0 || waveTargetItem.width <= 0 || positionLabelTargetItem.width <= 0 || durationLabelTargetItem.width <= 0)
            return;

        artTargetRect = targetRect(coverTargetItem);
        titleTargetRect = targetRect(titleTargetItem);
        channelTargetRect = targetRect(channelTargetItem);
        albumTargetRect = targetRect(albumTargetItem);
        timelineTargetRect = targetRect(timelineTargetItem);
        positionLabelTargetRect = targetRect(positionLabelTargetItem);
        durationLabelTargetRect = targetRect(durationLabelTargetItem);
        waveTargetRect = targetRect(waveTargetItem);
        morphTargetsReady = true;
    }

    implicitWidth: compactWidth + (pageWidth - compactWidth) * morph
    implicitHeight: compactHeight + (pageHeight - compactHeight) * morph
    visible: enabled && !fullscreen
    clip: true

    Component.onCompleted: compactDock = compact

    onMediaDockChanged: {
        if (mediaDock) {
            resetMorphTargets();
            selectDockTab();
            Qt.callLater(updateMorph);
        }
    }

    onExpandedChanged: {
        if (expanded) {
            selectDockTab();
            Qt.callLater(updateMorph);
        }
    }

    Behavior on morph {
        Anim {
            type: Anim.DefaultSpatial
        }
    }

    Behavior on pageWidth {
        enabled: root.expanded && root.morph === 1

        Anim {
            type: Anim.DefaultSpatial
        }
    }

    Behavior on pageHeight {
        enabled: root.expanded && root.morph === 1

        Anim {
            type: Anim.DefaultSpatial
        }
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
        x: root.mediaDock ? 0 : (root.width - width) / 2
        width: root.expandedWidth
        height: root.expandedHeight

        opacity: root.morph
        visible: opacity > 0 || root.mediaDock
        enabled: root.expanded

        transform: Translate {
            x: root.mediaDock && root.mediaSelected ? -root.Tokens.spacing.large * (1 - root.morph) : 0
            y: root.mediaDock && root.mediaSelected ? -root.Tokens.spacing.large * (1 - root.morph) : 0
        }

        Loader {
            id: expandedContent

            anchors.fill: parent
            active: root.expanded || root.morph > 0.01 || root.mediaDock

            onItemChanged: {
                root.resetMorphTargets();
                if (root.mediaDock) {
                    root.selectDockTab();
                    Qt.callLater(root.updateMorph);
                }
            }

            sourceComponent: Content {
                screenState: root.screenState
                facePicker: root.facePicker
                sharedMedia: root.mediaDock
                animatePages: root.expanded && root.morph === 1
                viewportWidth: root.expanded ? root.width : root.expandedWidth
                viewportHeight: root.expanded ? root.height : root.expandedHeight
            }
        }
    }

    Timer {
        interval: 80
        repeat: true
        running: root.mediaDock && !root.morphTargetsReady && root.morphAttempts < 50

        onTriggered: {
            root.morphAttempts++;
            root.updateMorph();
        }
    }

    Item {
        id: mediaClip

        readonly property var content: expandedContent.item
        readonly property rect viewport: content?.pageViewport ?? Qt.rect(0, 0, 0, 0)

        x: viewport.x * root.morph
        y: viewport.y * root.morph
        width: Math.max(0, root.width - x - Math.max(0, (content?.width ?? root.width) - viewport.x - viewport.width) * root.morph)
        height: Math.max(0, root.height - y - Math.max(0, (content?.height ?? root.height) - viewport.y - viewport.height) * root.morph)
        visible: root.mediaDock
        clip: true

        MediaDock {
            x: -mediaClip.x + (mediaClip.content?.mediaPageOffset ?? 0) * root.morph
            y: -mediaClip.y
            width: root.width
            height: root.height
            visible: root.mediaDock && !root.fullscreen
            compactWidth: root.compactWidth
            compactHeight: root.compactHeight
            active: !root.expanded
            morph: root.morph
            lyricMode: compact.lyricMode
            lyricsEnabled: compact.preferLyrics
            targetReady: root.morphTargetsReady
            artTargetRect: root.artTargetRect
            titleTargetRect: root.titleTargetRect
            channelTargetRect: root.channelTargetRect
            albumTargetRect: root.albumTargetRect
            timelineTargetRect: root.timelineTargetRect
            positionLabelTargetRect: root.positionLabelTargetRect
            durationLabelTargetRect: root.durationLabelTargetRect
            waveTargetRect: root.waveTargetRect
            enabled: root.mediaSelected || root.morph < 0.05
            onToggleLyrics: compact.preferLyrics = !compact.preferLyrics
        }
    }
}
