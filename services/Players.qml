pragma Singleton

import QtQml
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Caelestia
import Caelestia.Config
import Caelestia.I18n
import qs.components.misc

Singleton {
    id: root

    readonly property list<MprisPlayer> list: Mpris.players.values
    // Discovery stays complete for settings; only admitted sessions drive media UI.
    readonly property list<MprisPlayer> available: sessions.instances.filter(session => session.available).map(session => session.modelData)
    readonly property MprisPlayer active: available.includes(props.manualActive) ? props.manualActive : available.find(p => getIdentity(p) === GlobalConfig.services.defaultPlayer) ?? available[0] ?? null
    property alias manualActive: props.manualActive

    // Dedup key for progressive metadata (e.g. mpv-mpris/yt-dlp player fills title then artist later).
    property string lastNowPlayingKey: ""
    property bool initialized: false
    readonly property var acceptedTracks: JSON.parse(props.acceptedSessions)

    function rememberTrack(player: MprisPlayer, track: string): void {
        const name = player.dbusName;
        const previous = root.acceptedTracks.find(entry => entry.name === name);
        if ((previous?.track ?? "") === track)
            return;
        const entries = root.acceptedTracks.filter(entry => entry.name !== name && root.list.some(p => p.dbusName === entry.name));
        if (track)
            entries.push({
                name,
                track
            });
        props.acceptedSessions = JSON.stringify(entries);
    }

    function getIdentity(player: MprisPlayer): string {
        if (!player)
            return "";
        const alias = GlobalConfig.services.playerAliases.values.find(a => a.from === player.identity);
        return alias?.to ?? player.identity;
    }

    function getArtUrl(player: MprisPlayer): string {
        if (!player)
            return "";
        if (player.trackArtUrl)
            return player.trackArtUrl;

        const url = player.metadata["xesam:url"] ?? "";
        if (url.startsWith("https://www.youtube.com/watch")) {
            // Fallback for youtube
            const id = url.match(/[?&]v=([\w-]{11})/)?.[1];
            return id ? `https://img.youtube.com/vi/${id}/hqdefault.jpg` : "";
        }
        return "";
    }

    // Quickshell only emits postTrackChanged when trackid/url/title change, so late
    // artist updates (common with mpv-mpris + yt-dlp player) never retrigger it. Watch
    // title/artist too and toast once both are usable.
    function maybeToastNowPlaying(): void {
        if (!GlobalConfig.utilities.toasts.nowPlaying)
            return;

        const player = root.active;
        if (!player)
            return;

        const title = player.trackTitle ?? "";
        const artist = player.trackArtist ?? "";
        if (!title || !artist)
            return;

        const key = `${getIdentity(player)}\0${player.uniqueId}\0${title}\0${artist}`;
        if (key === lastNowPlayingKey)
            return;

        lastNowPlayingKey = key;
        Toaster.toast(Tr.tr("Now playing"), Tr.trCtx("%1 - %2", "track artist and title").arg(artist).arg(title), "music_note");
    }

    onActiveChanged: lastNowPlayingKey = ""
    onListChanged: {
        if (initialized)
            props.acceptedSessions = JSON.stringify(root.acceptedTracks.filter(entry => root.list.some(player => player.dbusName === entry.name)));
    }

    Connections {
        function onPostTrackChanged(): void {
            root.maybeToastNowPlaying();
        }

        function onTrackTitleChanged(): void {
            root.maybeToastNowPlaying();
        }

        function onTrackArtistChanged(): void {
            root.maybeToastNowPlaying();
        }

        target: root.active
    }

    PersistentProperties {
        id: props

        property MprisPlayer manualActive
        // Persist plain data rather than JavaScript objects owned by the old engine.
        property string acceptedSessions: "[]"

        reloadableId: "players"
        onLoaded: root.initialized = true
    }

    Variants {
        id: sessions

        model: root.list

        QtObject {
            id: session

            required property MprisPlayer modelData
            // A semantic key also survives QML engine reloads.
            readonly property string track: `${modelData.metadata["mpris:trackid"] ?? ""}\0${modelData.metadata["xesam:url"] ?? ""}\0${modelData.trackTitle}`
            readonly property string acceptedTrack: root.acceptedTracks.find(entry => entry.name === modelData.dbusName)?.track ?? ""
            readonly property bool available: modelData.playbackState !== MprisPlaybackState.Stopped && track === acceptedTrack

            readonly property Connections listener: Connections {
                function onPlaybackStateChanged(): void {
                    Qt.callLater(session.update);
                }

                target: session.modelData
            }

            function update(): void {
                // Metadata can precede playback state in the same D-Bus update.
                // Admit the final playing track, not a paused preview replacement.
                if (modelData.playbackState === MprisPlaybackState.Playing)
                    root.rememberTrack(modelData, track);
                else if (modelData.playbackState === MprisPlaybackState.Stopped || track !== acceptedTrack)
                    root.rememberTrack(modelData, "");
            }

            onTrackChanged: Qt.callLater(update)
            Component.onCompleted: Qt.callLater(update)
        }
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "mediaToggle"
        description: "Toggle media playback"
        onPressed: {
            const active = root.active;
            if (active && active.canTogglePlaying)
                active.togglePlaying();
        }
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "mediaPrev"
        description: "Previous track"
        onPressed: {
            const active = root.active;
            if (active && active.canGoPrevious)
                active.previous();
        }
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "mediaNext"
        description: "Next track"
        onPressed: {
            const active = root.active;
            if (active && active.canGoNext)
                active.next();
        }
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "mediaStop"
        description: "Stop media playback"
        onPressed: root.active?.stop()
    }

    IpcHandler {
        function getActive(prop: string): string {
            const active = root.active;
            return active ? active[prop] ?? "Invalid property" : "No active player";
        }

        function list(): string {
            return root.list.map(p => root.getIdentity(p)).join("\n");
        }

        function play(): void {
            const active = root.active;
            if (active?.canPlay)
                active.play();
        }

        function pause(): void {
            const active = root.active;
            if (active?.canPause)
                active.pause();
        }

        function playPause(): void {
            const active = root.active;
            if (active?.canTogglePlaying)
                active.togglePlaying();
        }

        function previous(): void {
            const active = root.active;
            if (active?.canGoPrevious)
                active.previous();
        }

        function next(): void {
            const active = root.active;
            if (active?.canGoNext)
                active.next();
        }

        function stop(): void {
            root.active?.stop();
        }

        target: "mpris"
    }
}
