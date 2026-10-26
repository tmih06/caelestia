pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.services

Item {
    id: root

    property bool active: true

    readonly property var player: Players.active
    readonly property bool recording: Recorder.running
    readonly property bool media: !recording && !!player
    readonly property bool playing: media && (player?.isPlaying ?? false)
    readonly property string dockId: media ? "media" : recording ? "recording" : "clock"
    readonly property string targetTab: media ? "media" : "dashboard"

    function formatElapsed(seconds: real): string {
        const total = Math.max(0, Math.floor(seconds));
        const hours = Math.floor(total / 3600);
        const minutes = Math.floor(total % 3600 / 60);
        const remainder = (total % 60).toString().padStart(2, "0");
        return hours > 0 ? `${hours}:${minutes.toString().padStart(2, "0")}:${remainder}` : `${minutes}:${remainder}`;
    }

    implicitWidth: media ? 348 : row.implicitWidth
    implicitHeight: media ? 26 : Math.max(24, row.implicitHeight)

    RowLayout {
        id: row

        anchors.fill: parent
        visible: !root.media
        spacing: Tokens.spacing.small

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
}
