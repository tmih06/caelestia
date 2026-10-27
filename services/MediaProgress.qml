pragma Singleton

import QtQuick
import Quickshell
import qs.services

Singleton {
    id: root

    readonly property var player: Players.active
    readonly property bool playing: !!player && (player.isPlaying ?? false)
    readonly property string identity: player ? `${player.uniqueId}\0${player.trackTitle}\0${player.trackArtist}` : ""
    readonly property real length: {
        // MprisPlayer.length falls back to the current position when the player
        // does not expose a length (Firefox drops mpris:length on some
        // interactions), which makes total time equal current time. Only trust
        // a supported length and keep the last known value for the same track.
        const value = player?.length ?? 0;
        if ((player?.lengthSupported ?? false) && Number.isFinite(value) && value > 0)
            return value;
        return cachedIdentity === identity && cachedLength > 0 ? cachedLength : 0;
    }
    readonly property bool hasProgress: !!player && (player?.positionSupported ?? false) && length > 0
    property string cachedIdentity: ""
    property real cachedLength: 0
    readonly property real progress: hasProgress ? Math.max(0, Math.min(1, displayPosition / length)) : 0
    readonly property real position: displayPosition
    property real displayPosition: 0
    property string trackKey: ""
    property real lastTick: 0
    property real seekGuardUntil: 0

    function currentTrackKey(): string {
        if (!player)
            return "";
        return `${player.uniqueId}\0${player.trackTitle}\0${player.trackArtist}\0${length}`;
    }

    function clampPosition(value: real): real {
        const position = Number.isFinite(value) ? value : 0;
        return root.length > 0 ? Math.max(0, Math.min(root.length, position)) : Math.max(0, position);
    }

    function updateCache(): void {
        if (!player)
            return;
        if (cachedIdentity !== identity) {
            cachedIdentity = identity;
            cachedLength = 0;
        }
        const value = player.length;
        if (player.lengthSupported && Number.isFinite(value) && value > 0)
            cachedLength = value;
    }

    function sync(forceReset: bool): void {
        if (!player) {
            trackKey = "";
            displayPosition = 0;
            return;
        }

        updateCache();
        const key = currentTrackKey();
        if (forceReset || key !== trackKey) {
            trackKey = key;
            displayPosition = clampPosition(player.position ?? 0);
            lastTick = playing ? Date.now() : 0;
            seekGuardUntil = 0;
            return;
        }

        const now = Date.now();
        if (playing && lastTick > 0)
            displayPosition = clampPosition(displayPosition + (now - lastTick) / 1000);
        lastTick = playing ? now : 0;

        if (now < seekGuardUntil)
            return;

        const current = player.position;
        if (!Number.isFinite(current))
            return;

        const position = clampPosition(current);
        // Ignore forward jumps while playing; MPRIS players commonly report a
        // position advanced by the paused duration on resume. While paused only
        // accept small corrections so a flaky player cannot reset the timeline.
        if (Math.abs(position - displayPosition) < 2)
            displayPosition = position;
        else if (playing && position < displayPosition - 2)
            displayPosition = position;
    }

    function seek(seconds: real): void {
        if (!player || !player.canSeek)
            return;
        const target = clampPosition(seconds);
        displayPosition = target;
        seekGuardUntil = Date.now() + 700;
        lastTick = playing ? Date.now() : 0;
        player.position = target;
    }

    onPlayerChanged: {
        cachedIdentity = "";
        cachedLength = 0;
        trackKey = "";
        displayPosition = 0;
        sync(true);
    }
    onPlayingChanged: {
        lastTick = playing ? Date.now() : 0;
        sync(false);
    }
    onIdentityChanged: sync(true)
    onLengthChanged: sync(true)

    Timer {
        interval: 200
        repeat: true
        running: !!root.player

        onTriggered: root.sync(false)
    }
}
