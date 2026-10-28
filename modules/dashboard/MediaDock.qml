pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services
import "media"

Item {
    id: root

    required property real compactWidth
    required property real compactHeight
    required property bool active
    required property real morph
    required property real lyricMode
    required property bool lyricsEnabled
    required property bool targetReady
    property rect artTargetRect
    property rect titleTargetRect
    property rect channelTargetRect
    property rect albumTargetRect
    property rect timelineTargetRect
    property rect positionLabelTargetRect
    property rect durationLabelTargetRect
    property rect waveTargetRect

    readonly property var player: Players.active
    readonly property bool playing: !!player && (player.isPlaying ?? false)
    readonly property string title: visibleText(player?.trackTitle) || visibleText(Players.getIdentity(player)) || Tr.tr("Unknown title")
    readonly property real length: MediaProgress.length
    readonly property bool hasProgress: MediaProgress.hasProgress
    readonly property real progress: MediaProgress.progress
    property bool waveHovered: false
    readonly property bool controlsVisible: !playing || waveHovered
    readonly property bool showingLyrics: lyricsEnabled && MediaLyrics.hasLyrics && MediaLyrics.currentIndex >= 0
    readonly property real lyricAmount: Math.max(0, Math.min(1, lyricMode))
    readonly property real ringAmount: Math.max(0, Math.min(1, lyricMode * (1 - morph)))
    readonly property bool marqueeOverflow: titleViewport.width > 0 && titleText.implicitWidth * titleText.scale > titleViewport.width + 1
    readonly property bool marqueeActive: enabled && visible && !lyricsEnabled && ((active && morph === 0) || morph === 1)
    readonly property real marqueeDistance: Math.max(0, titleText.implicitWidth * titleText.scale - titleViewport.width)
    readonly property real padding: Tokens.padding.medium
    readonly property real artSize: 24
    readonly property real controlWidth: 32
    readonly property real contentHeight: 26 + 10 * lyricAmount
    readonly property real titleHeight: 18 * (1 + lyricAmount)
    readonly property real titleColumnHeight: titleHeight + 8 * (1 - lyricAmount)
    readonly property real sourceY: Math.max(0, (compactHeight - contentHeight) / 2)
    readonly property real titleTop: sourceY + (contentHeight - titleColumnHeight) / 2
    readonly property real controlX: compactWidth - padding - controlWidth
    readonly property real titleX: padding + artSize + Tokens.spacing.small
    readonly property rect artSource: Qt.rect(padding, sourceY + 6 * lyricAmount, artSize, artSize)
    readonly property rect titleSource: Qt.rect(titleX, titleTop, Math.max(0, controlX - titleX - Tokens.spacing.small), titleHeight)
    readonly property rect timelineSource: Qt.rect(titleX, titleTop + titleHeight + 6 * (1 - lyricAmount), Math.max(0, controlX - titleX - Tokens.spacing.small), 2)
    readonly property rect waveSource: Qt.rect(controlX, sourceY + (contentHeight - 26) / 2, controlWidth, 26)
    readonly property rect artTarget: targetReady ? artTargetRect : artSource
    readonly property rect titleTarget: targetReady ? titleTargetRect : titleSource
    readonly property rect timelineTarget: targetReady ? timelineTargetRect : timelineSource
    readonly property rect waveTarget: targetReady ? waveTargetRect : waveSource

    signal toggleLyrics

    function visibleText(value: string): string {
        if (!value)
            return "";
        return value.replace(/[\s\u00A0\u034F\u1680\u2000-\u200F\u2028-\u202F\u205F-\u206F\u2800\u3164\uFEFF\uFFA0]+/g, " ").trim();
    }

    function lerp(from: real, to: real, t: real): real {
        return from + (to - from) * t;
    }

    function lengthStr(seconds: real): string {
        const total = Math.max(0, Math.floor(seconds));
        const hours = Math.floor(total / 3600);
        const mins = Math.floor(total / 60) % 60;
        const secs = (total % 60).toString().padStart(2, "0");
        return hours > 0 ? `${hours}:${mins.toString().padStart(2, "0")}:${secs}` : `${mins}:${secs}`;
    }

    function resetMarquee(): void {
        if (!titleText)
            return;
        marquee.stop();
        titleText.x = 0;
        if (marqueeOverflow && marqueeActive)
            marquee.restart();
    }

    function primaryAction(): void {
        if (!player)
            return;
        if (playing) {
            player.pause();
            return;
        }
        if (MediaProgress.length > 0 && MediaProgress.position >= MediaProgress.length - 0.5)
            MediaProgress.seek(0);
        player.play();
    }

    onMorphChanged: resetMarquee()
    onMarqueeActiveChanged: {
        if (marqueeActive)
            resetMarquee();
        else
            marquee.stop();
    }

    Item {
        id: art

        objectName: "sharedMediaArt"

        x: root.lerp(root.artSource.x, root.artTarget.x, root.morph)
        y: root.lerp(root.artSource.y, root.artTarget.y, root.morph)
        width: Math.max(1, root.artTarget.width)
        height: Math.max(1, root.artTarget.height)
        scale: root.lerp(root.artSource.width / Math.max(1, root.artTarget.width), 1, root.morph)
        transformOrigin: Item.TopLeft

        ClipRect {
            anchors.fill: parent
            radius: width / 2
            color: Colours.palette.m3surfaceContainerHighest

            Image {
                id: cover

                anchors.fill: parent
                source: Players.getArtUrl(root.player)
                sourceSize: Qt.size(Tokens.sizes.dashboard.mediaCoverArtSize, Tokens.sizes.dashboard.mediaCoverArtSize)
                asynchronous: true
                retainWhileLoading: true
                fillMode: Image.PreserveAspectCrop
            }

            MaterialIcon {
                anchors.centerIn: parent
                visible: cover.status !== Image.Ready
                text: "album"
                color: Colours.palette.m3primary
                fontStyle: Tokens.font.icon.small
            }

            MouseArea {
                anchors.fill: parent
                enabled: root.enabled && !!root.player && (root.morph === 0 || root.morph === 1)
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggleLyrics()
            }
        }
    }

    Item {
        id: titleViewport

        objectName: "sharedMediaTitle"

        x: root.lerp(root.titleSource.x, root.titleTarget.x, root.morph)
        y: root.lerp(root.titleSource.y, root.titleTarget.y, root.morph)
        width: root.lerp(root.titleSource.width, root.titleTarget.width, root.morph)
        height: root.lerp(root.titleSource.height, root.titleTarget.height, root.morph)
        clip: true

        onWidthChanged: root.resetMarquee()

        StyledText {
            id: titleText

            opacity: 1 - root.lyricAmount
            visible: opacity > 0
            y: (titleViewport.height - implicitHeight * scale) / 2 - 6 * root.lyricAmount
            width: implicitWidth
            text: root.title
            font.pointSize: Tokens.font.title.large.pointSize
            renderType: Text.QtRendering
            scale: root.lerp(Tokens.font.body.small.pointSize / Tokens.font.title.large.pointSize, 1, root.morph)
            transformOrigin: Item.TopLeft
            color: Colours.palette.m3onSurface
            verticalAlignment: Text.AlignVCenter

            onImplicitWidthChanged: root.resetMarquee()
        }

        Loader {
            id: lookupStatus

            anchors.centerIn: parent
            width: parent.width
            active: root.enabled && root.lyricAmount > 0 && !MediaLyrics.hasLyrics
            opacity: root.lyricAmount
            transform: Translate {
                y: 6 * (1 - root.lyricAmount)
            }

            sourceComponent: LyricsLookupStatus {
                compact: true
                centered: true
                active: root.enabled && root.visible && root.lyricAmount > 0
            }
        }

        ListView {
            id: lyricRoll

            readonly property real lineHeight: root.lerp(18, root.titleTarget.height, root.morph)

            function resetIndex(): void {
                // Model resets can overwrite currentIndex after lyrics arrive mid-track.
                currentIndex = Qt.binding(() => MediaLyrics.currentIndex);
                if (currentIndex >= 0)
                    positionViewAtIndex(currentIndex, ListView.Center);
            }

            objectName: "sharedMediaLyrics"
            anchors.fill: parent
            opacity: root.lyricAmount
            visible: opacity > 0 && MediaLyrics.hasLyrics
            transform: Translate {
                y: 6 * (1 - root.lyricAmount)
            }
            model: MediaLyrics.hasLyrics ? MediaLyrics.lines : []
            currentIndex: MediaLyrics.currentIndex
            interactive: false
            reuseItems: true
            cacheBuffer: 0
            highlightRangeMode: ListView.StrictlyEnforceRange
            preferredHighlightBegin: (height - lineHeight) / 2
            preferredHighlightEnd: (height + lineHeight) / 2
            highlightMoveDuration: root.enabled && root.visible && ((root.morph === 0 && Math.abs(root.lyricMode - 1) < 0.001) || root.morph === 1) ? Tokens.anim.durations.expressiveFastSpatial : 0
            highlightMoveVelocity: -1

            Component.onCompleted: Qt.callLater(resetIndex)
            onModelChanged: Qt.callLater(resetIndex)
            onCountChanged: Qt.callLater(resetIndex)

            delegate: Item {
                id: lyricRow

                required property string modelData
                property real effectScale: ListView.isCurrentItem ? 1 : 0
                property real scrollOffset: 0
                property real scrollDuration: 2500
                readonly property real overflow: Math.max(0, lyricText.implicitWidth * lyricText.scale - width)
                readonly property bool marqueeActive: root.enabled && root.visible && root.showingLyrics && ListView.isCurrentItem && ((root.morph === 0 && Math.abs(root.lyricMode - 1) < 0.001) || root.morph === 1)

                function updateScroll(): void {
                    lyricMarquee.stop();
                    if (!marqueeActive)
                        return;
                    scrollOffset = 0;
                    if (overflow <= 1)
                        return;
                    scrollDuration = Math.max(1200, overflow * 20);
                    const remaining = MediaLyrics.nextLineTime - MediaProgress.position;
                    if (root.playing && remaining > 0.5)
                        scrollDuration = Math.max(250, Math.min(scrollDuration, remaining * 1000 - 500));
                    lyricMarquee.restart();
                }

                width: lyricRoll.width
                height: lyricRoll.lineHeight

                layer.enabled: effectScale > 0 && root.enabled && root.visible && root.lyricAmount > 0
                layer.sourceRect: Qt.rect(0, 0, width, height)
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: Colours.palette.m3primary
                    shadowOpacity: 0.5 * lyricRow.effectScale
                    shadowBlur: 0.6 * lyricRow.effectScale
                    blur: 0.4 * lyricRow.effectScale
                }

                onMarqueeActiveChanged: updateScroll()
                onModelDataChanged: {
                    scrollOffset = 0;
                    Qt.callLater(updateScroll);
                }
                onOverflowChanged: {
                    scrollOffset = Math.min(scrollOffset, overflow);
                    if (marqueeActive)
                        Qt.callLater(updateScroll);
                }

                StyledText {
                    id: lyricText

                    x: Math.max(0, (lyricRow.width - implicitWidth * scale) / 2) - lyricRow.scrollOffset
                    y: (parent.height - implicitHeight * scale) / 2
                    width: implicitWidth
                    text: root.visibleText(parent.modelData) || ". . ."
                    font.pointSize: Tokens.font.title.large.pointSize
                    renderType: Text.QtRendering
                    scale: root.lerp(Tokens.font.body.small.pointSize / Tokens.font.title.large.pointSize, 1, root.morph)
                    transformOrigin: Item.TopLeft
                    color: lyricRow.ListView.isCurrentItem ? Colours.palette.m3primary : Colours.palette.m3outline
                    opacity: 0.5 + 0.5 * lyricRow.effectScale
                }

                Behavior on effectScale {
                    enabled: root.enabled && root.visible && root.lyricAmount > 0

                    Anim {
                        type: Anim.SlowEffects
                    }
                }

                SequentialAnimation {
                    id: lyricMarquee

                    loops: Animation.Infinite

                    PauseAnimation {
                        duration: 300
                    }

                    NumberAnimation {
                        target: lyricRow
                        property: "scrollOffset"
                        from: 0
                        to: lyricRow.overflow
                        duration: lyricRow.scrollDuration
                        easing.type: Easing.Linear
                    }

                    PauseAnimation {
                        duration: 1400
                    }

                    PropertyAction {
                        target: lyricRow
                        property: "scrollOffset"
                        value: 0
                    }
                }
            }
        }
    }

    StyledText {
        objectName: "sharedMediaChannel"

        x: root.lerp(root.titleSource.x, root.channelTargetRect.x, root.morph)
        y: root.lerp(root.titleSource.y + root.titleSource.height, root.channelTargetRect.y, root.morph)
        width: root.channelTargetRect.width
        height: root.channelTargetRect.height
        visible: root.targetReady && opacity > 0
        opacity: root.morph
        text: root.visibleText(root.player?.trackArtist) || Tr.tr("Unknown artist")
        font.pointSize: Tokens.font.title.medium.pointSize
        renderType: Text.QtRendering
        scale: root.morph
        transformOrigin: Item.TopLeft
        color: Colours.palette.m3onSurfaceVariant
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        clip: true
    }

    StyledText {
        objectName: "sharedMediaAlbum"

        x: root.lerp(root.titleSource.x, root.albumTargetRect.x, root.morph)
        y: root.lerp(root.titleSource.y + root.titleSource.height, root.albumTargetRect.y, root.morph)
        width: root.albumTargetRect.width
        height: root.albumTargetRect.height
        visible: root.targetReady && opacity > 0
        opacity: root.morph
        text: root.visibleText(root.player?.trackAlbum) || Tr.tr("Unknown album")
        font.pointSize: Tokens.font.title.medium.pointSize
        renderType: Text.QtRendering
        scale: root.morph
        transformOrigin: Item.TopLeft
        color: Colours.palette.m3secondary
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        clip: true
    }

    StyledSlider {
        id: timeline

        objectName: "sharedMediaTimeline"

        x: root.lerp(root.timelineSource.x, root.timelineTarget.x, root.morph)
        y: root.lerp(root.timelineSource.y, root.timelineTarget.y, root.morph)
        width: root.lerp(root.timelineSource.width, root.timelineTarget.width, root.morph)
        height: root.lerp(root.timelineSource.height, root.timelineTarget.height, root.morph)
        visible: !!root.player
        opacity: 1 - circularTimeline.opacity
        transform: Translate {
            y: 8 * root.ringAmount
        }
        enabled: root.targetReady && root.morph > 0.95 && root.hasProgress && (root.player?.canSeek ?? false)
        value: root.progress
        wavy: root.morph > 0.05
        indeterminate: !root.hasProgress
        animateWave: root.playing && root.enabled && root.visible && root.morph === 1
        waveFrequency: 5
        waveDuration: 2000
        radius: Math.round(height / 2)
        fgColour: Colours.palette.m3primary
        bgColour: Qt.alpha(Colours.palette.m3onSurface, 0.14)
        interactionOnMove: false
        animateFill: false
        handleHeight: root.lerp(4, root.timelineTarget.height * (dragging ? 3.5 : 3), root.morph)
        animateHandle: false
        onInteraction: value => MediaProgress.seek(value * root.length)
    }

    CircularProgress {
        id: circularTimeline

        objectName: "sharedMediaCircularTimeline"
        x: art.x + art.width * art.scale / 2 - width / 2
        y: art.y + art.height * art.scale / 2 - height / 2
        z: -1
        width: art.width * art.scale + 8
        height: art.height * art.scale + 8
        opacity: root.ringAmount
        visible: opacity > 0
        scale: 0.65 + 0.35 * root.ringAmount
        strokeWidth: 2
        spacing: 0
        value: visible ? root.progress : 0
        fgColour: root.hasProgress ? Colours.palette.m3primary : "transparent"
        bgColour: Qt.alpha(Colours.palette.m3onSurface, 0.14)
        hasEndIndicator: false
        wavePaused: true

        StyledRect {
            x: circularTimeline.width / 2 + circularTimeline.arcRadius * Math.sin(circularTimeline.value * Math.PI * 2) - width / 2
            y: circularTimeline.height / 2 - circularTimeline.arcRadius * Math.cos(circularTimeline.value * Math.PI * 2) - height / 2
            width: 4
            height: 4
            radius: 2
            visible: root.hasProgress
            color: Colours.palette.m3primary
        }
    }

    StyledText {
        objectName: "sharedMediaPositionLabel"

        x: root.lerp(root.timelineSource.x, root.positionLabelTargetRect.x, root.morph)
        y: root.lerp(root.timelineSource.y - height / 2, root.positionLabelTargetRect.y, root.morph)
        width: root.positionLabelTargetRect.width
        height: root.positionLabelTargetRect.height
        visible: root.targetReady && opacity > 0
        opacity: Math.max(0, (root.morph - 0.2) / 0.8)
        text: root.lengthStr(timeline.dragging ? timeline.pos * root.length : MediaProgress.position)
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.label.medium
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    StyledText {
        objectName: "sharedMediaDurationLabel"

        x: root.lerp(root.timelineSource.x + root.timelineSource.width - width, root.durationLabelTargetRect.x, root.morph)
        y: root.lerp(root.timelineSource.y - height / 2, root.durationLabelTargetRect.y, root.morph)
        width: root.durationLabelTargetRect.width
        height: root.durationLabelTargetRect.height
        visible: root.targetReady && opacity > 0
        opacity: Math.max(0, (root.morph - 0.2) / 0.8)
        text: root.hasProgress ? root.lengthStr(root.length) : "--:--"
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.label.medium
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    AudioWave {
        id: wave

        property real presence: root.controlsVisible ? 0 : 1

        objectName: "sharedMediaWaveform"

        x: root.lerp(root.waveSource.x, root.waveTarget.x, root.morph)
        y: root.lerp(root.waveSource.y, root.waveTarget.y, root.morph)
        width: root.waveSource.width
        height: root.waveSource.height
        running: root.active && root.enabled && root.visible && root.morph < 0.1 && (!root.controlsVisible || opacity > 0)
        visible: opacity > 0
        opacity: presence * Math.max(0, 1 - root.morph * 1.5)
        scale: root.controlsVisible ? 0.82 : 1

        transform: Scale {
            origin.x: 0
            origin.y: 0
            xScale: root.lerp(1, root.waveTarget.width / Math.max(1, root.waveSource.width), root.morph)
            yScale: root.lerp(1, root.waveTarget.height / Math.max(1, root.waveSource.height), root.morph)
        }

        Behavior on presence {
            Anim {
                type: Anim.DefaultEffects
            }
        }

        Behavior on scale {
            Anim {
                type: Anim.FastSpatial
            }
        }
    }

    Item {
        x: root.waveSource.x
        y: root.waveSource.y
        width: root.waveSource.width
        height: root.waveSource.height
        visible: opacity > 0
        opacity: (root.controlsVisible ? 1 : 0) * Math.max(0, 1 - root.morph * 5)
        scale: root.controlsVisible ? 1 : 0.82

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

        Item {
            anchors.centerIn: parent
            width: 24
            height: 24

            StyledRect {
                anchors.fill: parent
                radius: Tokens.rounding.full
                color: Colours.palette.m3onSurface
                opacity: root.waveHovered ? 0.08 : 0
            }

            MaterialIcon {
                anchors.centerIn: parent
                text: root.playing ? "pause" : "play_arrow"
                color: Colours.palette.m3primary
                fontStyle: Tokens.font.icon.small
            }
        }

        MouseArea {
            anchors.fill: parent
            enabled: root.active && root.morph < 0.1
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.PointingHandCursor
            onClicked: root.primaryAction()
        }
    }

    Item {
        x: root.waveSource.x
        y: root.waveSource.y
        width: root.waveSource.width
        height: root.waveSource.height
        visible: root.morph < 0.1

        HoverHandler {
            enabled: root.active

            onHoveredChanged: root.waveHovered = hovered
        }
    }

    SequentialAnimation {
        id: marquee

        loops: Animation.Infinite
        running: root.marqueeActive && root.marqueeOverflow

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
}
