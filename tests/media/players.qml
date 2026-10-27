import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.services

ShellRoot {
    // Instantiate services during construction, as the real shell's bindings do.
    readonly property MprisPlayer activePlayer: Players.active

    IpcHandler {
        function status(): string {
            return JSON.stringify({
                count: Players.list.length,
                available: Players.available.length,
                active: Players.active?.identity ?? "",
                title: Players.active?.trackTitle ?? "",
                position: MediaProgress.position
            });
        }

        function select(identity: string): void {
            Players.manualActive = Mpris.players.values.find(player => player.identity === identity) ?? null;
        }

        function reload(): void {
            Quickshell.reload(false);
        }

        target: "mediaProbe"
    }
}
