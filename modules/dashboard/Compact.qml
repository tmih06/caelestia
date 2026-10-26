pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import Caelestia.Services
import qs.components
import qs.components.images
import qs.services

Item {
    id: root

    readonly property var player: Players.active
    readonly property bool recording: Recorder.running
    readonly property bool media: !recording && !!player
    readonly property bool playing: media && (player?.isPlaying ?? false)
    readonly property string title: player?.trackTitle || Players.getIdentity(player) || Tr.tr("Unknown title")

    function formatElapsed(seconds: real): string {
        const total = Math.max(0, Math.floor(seconds));
        const hours = Math.floor(total / 3600);
        const minutes = Math.floor(total % 3600 / 60);
        const remainder = (total % 60).toString().padStart(2, "0");
        return hours > 0 ? `${hours}:${minutes.toString().padStart(2, "0")}:${remainder}` : `${minutes}:${remainder}`;
    }

    implicitWidth: row.implicitWidth
    implicitHeight: Math.max(24, row.implicitHeight)

    ServiceRef {
        service: Audio.cava
    }

    RowLayout {
        id: row

        anchors.centerIn: parent
        spacing: Tokens.spacing.small

        StyledRect {
            visible: root.recording
            implicitWidth: 7
            implicitHeight: 7
            radius: Tokens.rounding.full
            color: Recorder.paused ? Colours.palette.m3tertiary : Colours.palette.m3error
        }

        StyledText {
            visible: root.recording
            text: Recorder.paused ? Tr.tr("PAUSED") : Tr.tr("REC")
            color: Recorder.paused ? Colours.palette.m3tertiary : Colours.palette.m3error
            font: Tokens.font.label.small
        }

        StyledText {
            visible: root.recording
            text: root.formatElapsed(Recorder.elapsed)
            font: Tokens.font.mono.small
        }

        ClipRect {
            visible: root.media
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

        StyledText {
            visible: root.media
            Layout.maximumWidth: 150
            Layout.minimumWidth: 0
            text: root.title
            font: Tokens.font.body.small
            elide: Text.ElideRight
        }

        Row {
            visible: root.media && root.playing

            spacing: 2

            Repeater {
                model: 4

                StyledRect {
                    required property int index

                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: 2
                    implicitHeight: 2 + Math.max(0, Math.min(1, Audio.cava.values[index] ?? 0)) * 12
                    radius: Tokens.rounding.full
                    color: Colours.palette.m3primary

                    Behavior on implicitHeight {
                        Anim {
                            type: Anim.FastEffects
                        }
                    }
                }
            }
        }

        MaterialIcon {
            visible: root.media && !root.playing
            text: "pause"
            color: Colours.palette.m3onSurfaceVariant
            fontStyle: Tokens.font.icon.small
        }

        StyledRect {
            visible: !root.media && !root.recording
            implicitWidth: 6
            implicitHeight: 6
            radius: Tokens.rounding.full
            color: Colours.palette.m3primary
        }

        StyledText {
            visible: !root.media && !root.recording
            text: Time.timeStr
            color: Colours.palette.m3onSurface
            font: Tokens.font.body.builders.small.weight(Font.DemiBold).build()
        }
    }
}
