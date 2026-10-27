#!/usr/bin/env python3
"""Exercise the real Players singleton over MPRIS on a private D-Bus session.

Run: python3 tests/media/check.py
Requires a built plugin, Quickshell, a Wayland session, python-dbus and
python-gobject. No real media player, configuration, or playback is modified.
"""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import time

ROOT = Path(__file__).resolve().parents[2]
APP = "org.mpris.MediaPlayer2"
PLAYER = APP + ".Player"
PROPERTIES = "org.freedesktop.DBus.Properties"


def run_isolated() -> None:
    import dbus
    import dbus.service
    from dbus.mainloop.glib import DBusGMainLoop
    from gi.repository import GLib

    DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()
    # Prevent Qt from activating desktop portal processes on the test bus.
    portal_name = dbus.service.BusName("org.freedesktop.portal.Desktop", bus)

    class Player(dbus.service.Object):
        def __init__(self, suffix: str, identity: str):
            self.bus = dbus.SessionBus(private=True)
            self.bus.set_exit_on_disconnect(False)
            self.name = dbus.service.BusName(APP + "." + suffix, self.bus)
            super().__init__(self.bus, "/org/mpris/MediaPlayer2")
            self.properties = {
                APP: {
                    "Identity": dbus.String(identity),
                    "DesktopEntry": dbus.String("firefox"),
                    "CanQuit": dbus.Boolean(False),
                    "CanRaise": dbus.Boolean(False),
                    "HasTrackList": dbus.Boolean(False),
                    "SupportedUriSchemes": dbus.Array([], signature="s"),
                    "SupportedMimeTypes": dbus.Array([], signature="s"),
                },
                PLAYER: {
                    "PlaybackStatus": dbus.String("Stopped"),
                    "Metadata": self.metadata("Main video", "https://media.example/watch/main"),
                    "Position": dbus.Int64(10000000),
                    "CanControl": dbus.Boolean(True),
                    "CanPlay": dbus.Boolean(True),
                    "CanPause": dbus.Boolean(True),
                    "CanSeek": dbus.Boolean(True),
                    "CanGoNext": dbus.Boolean(False),
                    "CanGoPrevious": dbus.Boolean(False),
                    "Rate": dbus.Double(1.0),
                    "MinimumRate": dbus.Double(1.0),
                    "MaximumRate": dbus.Double(1.0),
                    "Volume": dbus.Double(1.0),
                },
            }

        @staticmethod
        def metadata(title: str, url: str, artist: str = "Fixture"):
            # Firefox reuses its track path; title/URL changes still identify a new track.
            return dbus.Dictionary({
                "mpris:trackid": dbus.ObjectPath("/org/mpris/MediaPlayer2/firefox"),
                "xesam:title": dbus.String(title),
                "xesam:url": dbus.String(url),
                "xesam:artist": dbus.Array([artist], signature="s"),
                "mpris:length": dbus.Int64(120000000),
            }, signature="sv")

        @dbus.service.method(PROPERTIES, in_signature="s", out_signature="a{sv}")
        def GetAll(self, interface):
            return self.properties[interface]

        @dbus.service.method(PROPERTIES, in_signature="ss", out_signature="v")
        def Get(self, interface, name):
            return self.properties[interface][name]

        @dbus.service.signal(PROPERTIES, signature="sa{sv}as")
        def PropertiesChanged(self, interface, changed, invalidated):
            pass

        def update(self, **properties) -> None:
            completed = threading.Event()

            def apply():
                self.properties[PLAYER].update(properties)
                self.PropertiesChanged(PLAYER, properties, [])
                completed.set()
                return False

            GLib.idle_add(apply)
            if not completed.wait(3):
                raise RuntimeError("fixture property update timed out")

        def close(self) -> None:
            self.remove_from_connection()
            del self.name
            self.bus.close()

    primary = Player("caelestia_primary", "Primary")
    secondary = Player("caelestia_secondary", "Secondary")
    loop = GLib.MainLoop()
    thread = threading.Thread(target=loop.run, daemon=True)
    thread.start()
    try:
        with tempfile.TemporaryDirectory(prefix="caelestia-media-test-") as directory:
            temp = Path(directory)
            for name in ("services", "components", "modules", "utils", "assets"):
                (temp / name).symlink_to(ROOT / name, target_is_directory=True)
            (temp / "shell.qml").write_text(Path(__file__).with_name("players.qml").read_text())
            config = temp / "config/caelestia"
            config.mkdir(parents=True)
            (config / "shell.json").write_text(json.dumps({
                "services": {"defaultPlayer": "Primary"},
                "utilities": {"toasts": {"nowPlaying": False}},
            }))
            env = os.environ.copy()
            env.update(
                QML2_IMPORT_PATH=str(ROOT / "build/qml"),
                QT_QPA_PLATFORM="wayland",
                XDG_CONFIG_HOME=str(temp / "config"),
                XDG_STATE_HOME=str(temp / "state"),
                XDG_CACHE_HOME=str(temp / "cache"),
            )
            env.pop("HYPRLAND_INSTANCE_SIGNATURE", None)
            with (temp / "shell.log").open("w+") as log:
                process = subprocess.Popen(
                    ["qs", "-p", str(temp / "shell.qml"), "--no-color"],
                    env=env, stdout=log, stderr=subprocess.STDOUT,
                )

                def ipc(method: str, *args: str):
                    result = subprocess.run(
                        ["qs", "ipc", "-p", str(temp / "shell.qml"), "call", "mediaProbe", method, *args],
                        env=env, capture_output=True, text=True, timeout=3,
                    )
                    if result.returncode:
                        raise RuntimeError(result.stdout + result.stderr)
                    if method == "status":
                        line = next((line for line in result.stdout.splitlines() if line.startswith("{")), None)
                        if line is None:
                            raise RuntimeError(result.stdout + result.stderr)
                        return json.loads(line)
                    return None

                def expect(label: str, **expected):
                    deadline = time.monotonic() + 3
                    state = None
                    while time.monotonic() < deadline:
                        if process.poll() is not None:
                            raise RuntimeError("shell exited during " + label)
                        try:
                            state = ipc("status")
                            if all(state.get(key) == value for key, value in expected.items()):
                                print("PASS", label)
                                return state
                        except RuntimeError:
                            pass  # IPC is temporarily unavailable during startup/reload.
                        time.sleep(0.025)
                    raise AssertionError(f"{label}: expected {expected}, received {state}")

                try:
                    expect("stopped players are discovery-only", count=2, available=0, active="")
                    ipc("select", "Primary")
                    expect("manual choice cannot revive stopped media", active="")
                    primary.update(PlaybackStatus=dbus.String("Paused"))
                    expect("unplayed paused metadata is not a session", available=0, active="")
                    primary.update(PlaybackStatus=dbus.String("Playing"))
                    expect("playing admits a session", available=1, active="Primary", title="Main video")
                    primary.update(PlaybackStatus=dbus.String("Paused"))
                    expect("pausing retains the same track", active="Primary", title="Main video")
                    primary.update(Metadata=primary.metadata("Main video", "https://media.example/watch/main", "Late artist"))
                    expect("late artist metadata preserves paused media", active="Primary", title="Main video")
                    ipc("reload")
                    time.sleep(0.2)
                    expect("reload retains paused admission", available=1, active="Primary", title="Main video")
                    primary.update(Metadata=primary.metadata("Hover preview", "https://media.example/"))
                    expect("paused preview replacement clears the old session", available=0, active="", position=0)
                    primary.update(Metadata=primary.metadata("Main video", "https://media.example/watch/main"))
                    expect("old paused metadata cannot revive a replaced session", available=0, active="")
                    primary.update(Metadata=primary.metadata("Another preview", "https://media.example/"))
                    expect("further previews cannot revive media", available=0, active="")
                    primary.update(
                        Metadata=primary.metadata("Next video", "https://media.example/watch/next"),
                        PlaybackStatus=dbus.String("Playing"),
                    )
                    expect("actual playback admits the next track", active="Primary", title="Next video")
                    primary.update(
                        Metadata=primary.metadata("Preview during stop", "https://media.example/"),
                        PlaybackStatus=dbus.String("Paused"),
                    )
                    expect("batched metadata/state changes use final paused state", available=0, active="")
                    primary.update(PlaybackStatus=dbus.String("Playing"))
                    expect("resume admits playback", active="Primary")
                    primary.update(PlaybackStatus=dbus.String("Stopped"))
                    expect("stop clears retained metadata and progress", available=0, active="", position=0)
                    primary.update(PlaybackStatus=dbus.String("Paused"))
                    expect("paused state after stop does not revive a session", available=0, active="")
                    primary.update(PlaybackStatus=dbus.String("Playing"))
                    secondary.update(PlaybackStatus=dbus.String("Playing"))
                    expect("multiple playing sessions remain eligible", available=2, active="Primary")
                    primary.update(PlaybackStatus=dbus.String("Stopped"))
                    expect("stopped manual selection falls back to another session", available=1, active="Secondary")
                    secondary.close()
                    expect("disconnected player is removed", count=1, available=0, active="", position=0)
                    secondary = Player("caelestia_secondary", "Secondary")
                    secondary.update(PlaybackStatus=dbus.String("Paused"))
                    expect("reconnected paused player needs fresh playback", count=2, available=0, active="")
                    print("MEDIA_LIFECYCLE_PASS")
                except Exception:
                    log.seek(0)
                    print(log.read(), file=sys.stderr)
                    raise
                finally:
                    process.terminate()
                    try:
                        process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()
    finally:
        loop.quit()
        thread.join(timeout=3)
        # Keep the private bus name alive until the shell has exited.
        del portal_name


if __name__ == "__main__":
    if sys.argv[1:] == ["--isolated"]:
        run_isolated()
    elif sys.argv[1:]:
        raise SystemExit("usage: python3 tests/media/check.py")
    else:
        raise SystemExit(subprocess.call(["dbus-run-session", "--", sys.executable, str(Path(__file__).resolve()), "--isolated"]))
