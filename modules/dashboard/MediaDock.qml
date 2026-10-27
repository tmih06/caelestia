pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services

Item {
    id: root

    required property real compactWidth
    required property real compactHeight
    required property bool active
    required property real morph
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
    property bool hovered: false
    readonly property bool controlsVisible: !playing || hovered
    readonly property bool marqueeOverflow: titleViewport.width > 0 && titleText.implicitWidth * titleText.scale > titleViewport.width + 1
    readonly property bool marqueeActive: enabled && visible && ((active && morph === 0) || morph === 1)
    readonly property real marqueeDistance: Math.max(0, titleText.implicitWidth * titleText.scale - titleViewport.width)
    readonly property real padding: Tokens.padding.medium
    readonly property real artSize: 24
    readonly property real controlWidth: 32
    readonly property real contentHeight: 26
    readonly property real titleHeight: 18
    readonly property real titleColumnHeight: titleHeight + 8
    readonly property real sourceY: Math.max(0, (compactHeight - contentHeight) / 2)
    readonly property real titleTop: sourceY + (contentHeight - titleColumnHeight) / 2
    readonly property real controlX: compactWidth - padding - controlWidth
    readonly property real titleX: padding + artSize + Tokens.spacing.small
    readonly property rect artSource: Qt.rect(padding, sourceY, artSize, artSize)
    readonly property rect titleSource: Qt.rect(titleX, titleTop, Math.max(0, controlX - titleX - Tokens.spacing.small), titleHeight)
    readonly property rect timelineSource: Qt.rect(titleX, titleTop + titleHeight + 6, Math.max(0, controlX - titleX - Tokens.spacing.small), 2)
    readonly property rect waveSource: Qt.rect(controlX, sourceY, controlWidth, contentHeight)
    readonly property rect artTarget: targetReady ? artTargetRect : artSource
    readonly property rect titleTarget: targetReady ? titleTargetRect : titleSource
    readonly property rect timelineTarget: targetReady ? timelineTargetRect : timelineSource
    readonly property rect waveTarget: targetReady ? waveTargetRect : waveSource

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
                opacity: root.hovered ? 0.08 : 0
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
        x: 0
        y: 0
        width: root.compactWidth
        height: root.compactHeight
        visible: root.morph < 0.1

        HoverHandler {
            enabled: root.active

            onHoveredChanged: root.hovered = hovered
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
