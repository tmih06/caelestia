pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia
import qs.utils

Singleton {
    id: root

    // A shell-lifetime session: PiG persists the transcript under this id, so
    // follow-up prompts have the previous turns in context. Clearing starts a
    // fresh session.
    property string sessionId: "caelestia-chat-" + Date.now()
    property var messages: []
    property string pendingPrompt: ""
    property bool busy: false
    property string error: ""
    property bool timedOut: false
    property bool cancelling: false

    readonly property string binary: Quickshell.env("CAELESTIA_ASSISTANT") || `${Paths.home}/.local/bin/assistant`

    function send(prompt: string): void {
        const text = String(prompt ?? "").trim();
        if (!text || busy)
            return;

        messages = messages.concat([{
            role: "user",
            text
        }]);
        pendingPrompt = text;
        error = "";
        timedOut = false;
        busy = true;
        agent.running = true;
    }

    function cancel(): void {
        if (!busy)
            return;

        cancelling = true;
        agent.running = false;
        busy = false;
        pendingPrompt = "";
        if (messages.length > 0 && messages[messages.length - 1].role === "user")
            messages = messages.slice(0, -1);
    }

    function clear(): void {
        if (busy)
            return;
        messages = [];
        error = "";
        sessionId = "caelestia-chat-" + Date.now();
    }

    Process {
        id: agent

        command: [root.binary, "--print", "--session-id", root.sessionId, "--", root.pendingPrompt]
        workingDirectory: Paths.home
        running: false

        stdout: StdioCollector {
            id: stdout
        }

        stderr: StdioCollector {
            id: stderr
        }

        onExited: code => {
            root.busy = false;
            if (root.cancelling) {
                root.cancelling = false;
                return;
            }
            if (root.timedOut) {
                root.timedOut = false;
                root.error = "Assistant timed out";
                return;
            }
            if (code !== 0) {
                const detail = stderr.text.trim();
                root.error = detail || `Assistant exited with code ${code}`;
                return;
            }

            const reply = stdout.text.trim();
            if (!reply) {
                root.error = "Assistant returned an empty response";
                return;
            }

            root.messages = root.messages.concat([{
                role: "assistant",
                text: reply
            }]);
        }
    }

    Timer {
        interval: 90000
        running: root.busy

        onTriggered: {
            root.timedOut = true;
            agent.running = false;
        }
    }
}
