pragma Singleton

import QtQml
import Quickshell
import Caelestia.Services
import qs.services

Singleton {
    id: root

    readonly property var player: Players.active
    readonly property string trackKey: player ? `${player.trackArtist}\0${player.trackTitle}\0${player.trackAlbum}` : ""
    readonly property real duration: MediaProgress.length
    readonly property list<string> lines: Lyrics.lyrics
    readonly property bool hasLyrics: !!player && Lyrics.hasLyrics && !Lyrics.loading
    readonly property int currentIndex: {
        if (!hasLyrics || !lines.length)
            return -1;
        Lyrics.offset; // The native lookup applies the offset but does not expose that dependency.
        // Show the first upcoming line during an intro instead of reverting to the title.
        return Math.max(0, Lyrics.indexForTime(MediaProgress.position));
    }
    readonly property real nextLineTime: {
        if (currentIndex < 0 || currentIndex + 1 >= lines.length)
            return -1;
        Lyrics.offset;
        return Lyrics.timeForIndex(currentIndex + 1);
    }

    function updateTrack(): void {
        const p = player;
        if (p)
            Lyrics.setTrack(p.trackArtist, p.trackTitle, p.trackAlbum, duration);
        else
            Lyrics.clearTrack();
    }

    onTrackKeyChanged: {
        // Invalidate old lines immediately, before the backend's debounced lookup.
        Lyrics.clearTrack();
        Qt.callLater(updateTrack);
    }
    onDurationChanged: Qt.callLater(updateTrack)
    Component.onCompleted: Qt.callLater(updateTrack)
}
