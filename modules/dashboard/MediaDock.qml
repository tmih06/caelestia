pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.images
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
    property rect timelineTargetRect
    property rect waveTargetRect

    readonly property var player: Players.active
    readonly property bool playing: !!player && (player.isPlaying ?? false)
    readonly property string title: visibleText(player?.trackTitle) || visibleText(Players.getIdentity(player)) || Tr.tr("Unknown title")
    readonly property real position: {
        const value = player?.position ?? 0;
        return Number.isFinite(value) && value > 0 ? value : 0;
    }
    readonly property real length: {
        const value = player?.length ?? 0;
        return Number.isFinite(value) && value > 0 ? value : 0;
    }
    readonly property bool hasProgress: !!player && (player?.positionSupported ?? false) && length > 0
    readonly property real progress: hasProgress ? Math.max(0, Math.min(1, position / length)) : 0
    property bool hovered: false
    readonly property bool controlsVisible: !playing || hovered
    readonly property bool marqueeOverflow: titleViewport.width > 0 && titleText.implicitWidth > titleViewport.width + 1
    readonly property real marqueeDistance: Math.max(0, titleText.implicitWidth - titleViewport.width)
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

    function resetMarquee(): void {
        if (!titleText)
            return;
        titleText.x = 0;
        if (marqueeOverflow && active && morph < 0.05)
            marquee.restart();
    }

    function primaryAction(): void {
        if (!player)
            return;
        if (playing) {
            player.pause();
            return;
        }
        if (length > 0 && position >= length - 0.5 && player.canSeek && player.positionSupported)
            player.position = 0;
        player.play();
    }

    onMorphChanged: {
        if (morph > 0.05) {
            marquee.stop();
            titleText.x = 0;
        } else if (marqueeOverflow) {
            marquee.restart();
        }
    }

    Timer {
        interval: GlobalConfig.dashboard.mediaUpdateInterval
        repeat: true
        running: root.active && root.playing && (root.player?.positionSupported ?? false)
        triggeredOnStart: true

        onTriggered: root.player?.positionChanged()
    }

    Item {
        id: art

        x: root.lerp(root.artSource.x, root.artTarget.x, root.morph)
        y: root.lerp(root.artSource.y, root.artTarget.y, root.morph)
        width: root.lerp(root.artSource.width, root.artTarget.width, root.morph)
        height: root.lerp(root.artSource.height, root.artTarget.height, root.morph)

        ClipRect {
            anchors.fill: parent
            radius: root.lerp(Tokens.rounding.small, Tokens.rounding.extraLarge, root.morph)
            color: Colours.palette.m3surfaceContainerHighest

            FadeImage {
                id: cover

                anchors.fill: parent
                source: Players.getArtUrl(root.player)
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
            font.pointSize: root.lerp(Tokens.font.body.small.pointSize, Tokens.font.title.large.pointSize, root.morph)
            color: Colours.palette.m3onSurface
            verticalAlignment: Text.AlignVCenter

            onImplicitWidthChanged: root.resetMarquee()
        }
    }

    Item {
        x: root.lerp(root.timelineSource.x, root.timelineTarget.x, root.morph)
        y: root.lerp(root.timelineSource.y, root.timelineTarget.y + (root.timelineTarget.height - Math.min(6, root.timelineTarget.height)) / 2, root.morph)
        width: root.lerp(root.timelineSource.width, root.timelineTarget.width, root.morph)
        height: root.lerp(root.timelineSource.height, Math.min(6, root.timelineTarget.height), root.morph)
        visible: root.hasProgress

        StyledRect {
            anchors.fill: parent
            radius: height / 2
            color: Qt.alpha(Colours.palette.m3onSurface, 0.14)
        }

        StyledRect {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width * root.progress
            height: parent.height
            radius: height / 2
            color: Colours.palette.m3primary
        }

        StyledRect {
            anchors.verticalCenter: parent.verticalCenter
            x: Math.max(0, Math.min(parent.width - width, parent.width * root.progress - width / 2))
            width: 4
            height: 4
            radius: height / 2
            color: Colours.palette.m3primary
        }
    }

    AudioWave {
        id: wave

        x: root.lerp(root.waveSource.x, root.waveTarget.x, root.morph)
        y: root.lerp(root.waveSource.y, root.waveTarget.y, root.morph)
        width: root.waveSource.width
        height: root.waveSource.height
        running: root.active && root.playing && root.morph < 0.1
        visible: root.playing
        opacity: root.controlsVisible ? 0 : 1
        scale: root.controlsVisible ? 0.82 : 1

        transform: Scale {
            origin.x: 0
            origin.y: 0
            xScale: root.lerp(1, root.waveTarget.width / Math.max(1, root.waveSource.width), root.morph)
            yScale: root.lerp(1, root.waveTarget.height / Math.max(1, root.waveSource.height), root.morph)
        }

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

    Item {
        x: root.waveSource.x
        y: root.waveSource.y
        width: root.waveSource.width
        height: root.waveSource.height
        visible: root.morph < 0.1
        opacity: root.controlsVisible ? 1 : 0
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
        running: root.active && root.morph < 0.05 && root.marqueeOverflow

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
