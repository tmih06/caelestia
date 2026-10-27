import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Mpris
import Caelestia.Components
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services

ColumnLayout {
    id: root

    property bool sharedMedia: false

    readonly property bool hasUnknownLength: !MediaProgress.hasProgress || MediaProgress.length > 2147483647

    function playPause(): void {
        const player = Players.active;
        if (!player)
            return;
        if (!player.isPlaying && MediaProgress.length > 0 && MediaProgress.position >= MediaProgress.length - 0.5)
            MediaProgress.seek(0);
        player.togglePlaying();
    }

    function lengthStr(length: int): string {
        if (length < 0)
            return "-1:-1";

        const hours = Math.floor(length / 3600);
        const mins = Math.floor((length % 3600) / 60);
        const secs = Math.floor(length % 60).toString().padStart(2, "0");

        if (hours > 0)
            return `${hours}:${mins.toString().padStart(2, "0")}:${secs}`;
        return `${mins}:${secs}`;
    }

    spacing: Tokens.spacing.extraSmall

    StyledText {
        id: titleLabel

        objectName: "dockMorphTitle"

        opacity: root.sharedMedia ? 0 : 1
        Layout.fillWidth: true
        text: Players.active?.trackTitle ?? ""
        font: Tokens.font.title.large
        elide: Text.ElideRight
        animate: !root.sharedMedia
    }

    StyledText {
        objectName: "dockMorphChannel"
        opacity: root.sharedMedia ? 0 : 1
        Layout.fillWidth: true
        text: Players.active?.trackArtist || Tr.tr("Unknown artist")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.title.medium
        elide: Text.ElideRight
        animate: !root.sharedMedia
    }

    StyledText {
        objectName: "dockMorphAlbum"
        opacity: root.sharedMedia ? 0 : 1
        Layout.fillWidth: true
        text: Players.active?.trackAlbum || Tr.tr("Unknown album")
        color: Colours.palette.m3secondary
        font: Tokens.font.title.medium
        elide: Text.ElideRight
        animate: !root.sharedMedia
    }

    RowLayout {
        Layout.topMargin: Tokens.spacing.extraLargeIncreased
        Layout.fillWidth: true
        spacing: Tokens.spacing.small

        TextMetrics {
            id: timeMetrics

            text: MediaProgress.player ? root.lengthStr(Math.max(MediaProgress.position, root.hasUnknownLength ? 0 : MediaProgress.length)).replace(/[1-9]/g, "0") : "00:00"
            font: Tokens.font.label.medium
        }

        StyledText {
            id: positionLabel

            objectName: "dockMorphPositionLabel"
            opacity: root.sharedMedia ? 0 : 1

            Layout.preferredWidth: timeMetrics.width
            text: root.lengthStr(MediaProgress.position)
            color: Colours.palette.m3onSurfaceVariant
            font: timeMetrics.font
            horizontalAlignment: Text.AlignHCenter
        }

        StyledSlider {
            id: positionSlider

            objectName: "dockMorphTimeline"

            opacity: root.sharedMedia ? 0 : 1
            Layout.fillWidth: true
            value: MediaProgress.progress
            enabled: (Players.active?.canSeek ?? false) && !root.hasUnknownLength
            wavy: true
            animateWave: !root.sharedMedia && root.enabled && root.visible && MediaProgress.playing
            waveFrequency: 5
            waveDuration: 2000
            interactionOnMove: false
            onInteraction: value => MediaProgress.seek(value * MediaProgress.length)

            Binding {
                target: positionLabel
                property: "text"
                value: root.lengthStr(positionSlider.pos * MediaProgress.length)
                when: positionSlider.dragging
            }
        }

        StyledText {
            objectName: "dockMorphDurationLabel"
            opacity: root.sharedMedia ? 0 : 1
            Layout.preferredWidth: timeMetrics.width
            text: root.hasUnknownLength ? "--:--" : root.lengthStr(MediaProgress.length)
            color: Colours.palette.m3onSurfaceVariant
            font: timeMetrics.font
            horizontalAlignment: Text.AlignHCenter
        }
    }

    ButtonRow {
        Layout.topMargin: Tokens.spacing.largeIncreased
        Layout.fillWidth: true
        spacing: Tokens.spacing.extraSmall

        IconButton {
            type: IconButton.Tonal
            icon: "shuffle"
            isRound: true
            shapeMorph: true
            checked: Players.active?.shuffle ?? false
            font: Tokens.font.icon.builders.medium.weight(Font.Medium).build()
            disabled: !Players.active?.shuffleSupported
            onClicked: Players.active.shuffle = !Players.active?.shuffle
            implicitWidth: Math.round(implicitHeight * 0.9)
        }

        IconButton {
            id: previousBtn

            type: IconButton.Tonal
            icon: "skip_previous"
            isRound: true
            shapeMorph: true
            font: Tokens.font.icon.large
            disabled: !Players.active?.canGoPrevious
            onClicked: Players.active?.previous()
        }

        IconButton {
            id: playPauseBtn

            icon: Players.active?.isPlaying ? "pause" : "play_arrow"
            isRound: true
            shapeMorph: true
            fillWidth: true
            checked: Players.active?.isPlaying ?? false
            font: Tokens.font.icon.large
            disabled: !Players.active?.canTogglePlaying
            onClicked: root.playPause()
        }

        IconButton {
            id: nextBtn

            type: IconButton.Tonal
            icon: "skip_next"
            isRound: true
            shapeMorph: true
            font: Tokens.font.icon.large
            disabled: !Players.active?.canGoNext
            onClicked: Players.active?.next()
        }

        IconButton {
            type: IconButton.Tonal
            icon: Players.active?.loopState === MprisLoopState.Track ? "repeat_one" : "repeat"
            isRound: true
            shapeMorph: true
            checked: Players.active?.loopState === MprisLoopState.Track || Players.active?.loopState === MprisLoopState.Playlist
            font: Tokens.font.icon.builders.medium.weight(Font.Medium).build()
            disabled: !Players.active?.loopSupported
            onClicked: {
                const state = Players.active.loopState;
                if (state === MprisLoopState.None)
                    Players.active.loopState = MprisLoopState.Track;
                else if (state === MprisLoopState.Track)
                    Players.active.loopState = MprisLoopState.Playlist;
                else
                    Players.active.loopState = MprisLoopState.None;
            }
            implicitWidth: Math.round(implicitHeight * 0.9)
        }
    }
}
