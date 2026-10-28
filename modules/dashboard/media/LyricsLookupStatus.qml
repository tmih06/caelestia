pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import Caelestia.Services
import qs.components
import qs.services

ColumnLayout {
    id: root

    property bool compact: false
    property bool centered: false
    property bool active: true
    property real elapsedMs: 0

    readonly property int phase: Number(Lyrics.lookupState)
    readonly property var attempts: Lyrics.lookupAttempts
    readonly property var currentAttempt: {
        const list = root.attempts;
        if (!list || list.length === 0)
            return null;
        if (root.phase === Lyrics.Fetching) {
            for (let i = list.length - 1; i >= 0; --i) {
                if (root.attemptState(list[i]) === Lyrics.Fetching)
                    return list[i];
            }
        }
        return list[list.length - 1];
    }
    readonly property string currentSource: String(root.currentAttempt?.source ?? "")
    readonly property bool currentCached: root.currentAttempt?.cached ?? false
    readonly property string currentStatus: root.statusLabel(root.phase)
    readonly property bool elapsedVisible: root.phase >= Lyrics.Fetching && root.phase <= Lyrics.Failed
    readonly property string elapsedText: root.elapsedVisible ? root.formatDuration(root.elapsedMs) : ""

    function syncElapsed(): void {
        const value = Number(Lyrics.lookupElapsedMs);
        root.elapsedMs = Number.isFinite(value) ? Math.max(0, value) : 0;
    }

    function formatDuration(ms: real): string {
        if (!Number.isFinite(ms) || ms < 0)
            return "";
        if (ms < 1000)
            return Tr.tr("%1 ms").arg(Math.round(ms));
        return Tr.tr("%1 s").arg((ms / 1000).toFixed(1));
    }

    function attemptState(attempt: var): int {
        const value = Number(attempt?.state);
        return Number.isFinite(value) ? Math.floor(value) : -1;
    }

    function attemptDurationText(attempt: var): string {
        const state = root.attemptState(attempt);
        if (state < 0)
            return "";

        let ms = Number(attempt?.elapsedMs);
        if (state === Lyrics.Fetching) {
            const started = Number(attempt?.startedMs);
            if (Number.isFinite(started))
                ms = Math.max(0, root.elapsedMs - started);
        }

        return Number.isFinite(ms) ? root.formatDuration(ms) : "";
    }

    function attemptErrorLabel(attempt: var): string {
        const error = String(attempt?.error ?? "");
        return error.length > 0 ? Tr.tr("Error: %1").arg(error) : "";
    }

    function statusLabel(state: int): string {
        switch (state) {
        case Lyrics.Idle:
            // A known track with Idle details is metadata preparation before the debounced lookup.
            return Lyrics.trackTitle.length > 0 ? Tr.tr("Preparing lookup") : Tr.tr("No lookup in progress");
        case Lyrics.Fetching:
            return Tr.tr("Fetching lyrics");
        case Lyrics.Success:
            return Tr.tr("Lyrics found");
        case Lyrics.NotFound:
            return Tr.tr("No lyrics found");
        case Lyrics.Failed:
            return Tr.tr("Lyrics lookup failed");
        default:
            return Tr.tr("Unknown lookup status");
        }
    }

    function stateLabel(state: int): string {
        switch (state) {
        case Lyrics.Idle:
            return Tr.tr("Idle");
        case Lyrics.Fetching:
            return Tr.tr("Fetching");
        case Lyrics.Success:
            return Tr.tr("Success");
        case Lyrics.NotFound:
            return Tr.tr("Not found");
        case Lyrics.Failed:
            return Tr.tr("Failed");
        default:
            return Tr.tr("Unknown");
        }
    }

    function phaseColour(state: int): color {
        switch (state) {
        case Lyrics.Fetching:
            return Colours.palette.m3onSurfaceVariant;
        case Lyrics.Success:
            return Colours.palette.m3primary;
        case Lyrics.NotFound:
            return Colours.palette.m3outline;
        case Lyrics.Failed:
            return Colours.palette.m3error;
        default:
            return Colours.palette.m3onSurfaceVariant;
        }
    }

    spacing: 0

    Component.onCompleted: root.syncElapsed()
    onActiveChanged: root.syncElapsed()
    onVisibleChanged: {
        if (root.visible)
            root.syncElapsed();
    }

    ColumnLayout {
        id: compactView

        Layout.fillWidth: true
        visible: root.compact
        spacing: 0

        RowLayout {
            id: compactMeta

            Layout.fillWidth: !root.centered
            Layout.alignment: root.centered ? Qt.AlignHCenter : Qt.AlignLeft
            spacing: Tokens.spacing.extraSmall
            visible: root.currentSource.length > 0 || root.elapsedVisible

            StyledText {
                Layout.fillWidth: !root.centered
                text: root.currentSource
                visible: root.currentSource.length > 0
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.label.small
                elide: Text.ElideRight
            }

            Item {
                Layout.fillWidth: !root.centered
                visible: !root.centered
            }

            StyledText {
                text: root.elapsedText
                visible: root.elapsedVisible
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.mono.small
            }
        }

        StyledText {
            Layout.fillWidth: true
            text: root.currentStatus
            color: root.phaseColour(root.phase)
            font: Tokens.font.label.small
            elide: Text.ElideRight
            horizontalAlignment: root.centered ? Text.AlignHCenter : Text.AlignLeft
        }
    }

    ColumnLayout {
        id: fullView

        Layout.fillWidth: true
        visible: !root.compact
        spacing: Tokens.spacing.small

        ColumnLayout {
            id: fullCurrent

            Layout.fillWidth: true
            spacing: Tokens.spacing.extraSmall

            RowLayout {
                id: fullMeta

                Layout.fillWidth: !root.centered
                Layout.alignment: root.centered ? Qt.AlignHCenter : Qt.AlignLeft
                spacing: Tokens.spacing.small
                visible: root.currentSource.length > 0 || root.currentCached || root.elapsedVisible

                StyledText {
                    text: root.currentSource.length > 0 ? Tr.tr("Source: %1").arg(root.currentSource) : ""
                    visible: root.currentSource.length > 0
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.label.small
                }

                StyledText {
                    text: Tr.tr("Cached")
                    visible: root.currentCached
                    color: Colours.palette.m3tertiary
                    font: Tokens.font.label.small
                }

                Item {
                    Layout.fillWidth: !root.centered
                    visible: !root.centered
                }

                StyledText {
                    text: root.elapsedText
                    visible: root.elapsedVisible
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.mono.small
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: root.currentStatus
                color: root.phaseColour(root.phase)
                font: Tokens.font.body.small
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                horizontalAlignment: root.centered ? Text.AlignHCenter : Text.AlignLeft
            }
        }

        Loader {
            id: historyLoader

            Layout.fillWidth: true
            active: root.active && root.visible && !root.compact && (root.attempts?.length ?? 0) > 0
            visible: active

            sourceComponent: ColumnLayout {
                width: historyLoader.width
                spacing: Tokens.spacing.extraSmall

                StyledText {
                    text: Tr.tr("Lookup attempts")
                    color: Colours.palette.m3outline
                    font: Tokens.font.label.small
                }

                Repeater {
                    model: root.attempts

                    ColumnLayout {
                        id: attemptRow

                        required property var modelData

                        readonly property int attemptPhase: root.attemptState(attemptRow.modelData)
                        readonly property string attemptSource: String(attemptRow.modelData?.source ?? "")
                        readonly property bool attemptCached: attemptRow.modelData?.cached ?? false
                        readonly property string attemptDuration: root.attemptDurationText(attemptRow.modelData)
                        readonly property string errorLabel: root.attemptErrorLabel(attemptRow.modelData)

                        Layout.fillWidth: true
                        spacing: Tokens.spacing.extraSmall

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.spacing.small

                            StyledText {
                                text: attemptRow.attemptSource
                                visible: attemptRow.attemptSource.length > 0
                                color: Colours.palette.m3onSurfaceVariant
                                font: Tokens.font.label.small
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: root.stateLabel(attemptRow.attemptPhase)
                                color: root.phaseColour(attemptRow.attemptPhase)
                                font: Tokens.font.label.small
                                elide: Text.ElideRight
                            }

                            StyledText {
                                text: Tr.tr("Cached")
                                visible: attemptRow.attemptCached
                                color: Colours.palette.m3tertiary
                                font: Tokens.font.label.small
                            }

                            StyledText {
                                text: attemptRow.attemptDuration
                                visible: attemptRow.attemptDuration.length > 0
                                color: Colours.palette.m3onSurfaceVariant
                                font: Tokens.font.mono.small
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: attemptRow.errorLabel
                            visible: attemptRow.errorLabel.length > 0
                            color: Colours.palette.m3error
                            font: Tokens.font.label.small
                            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                        }
                    }
                }
            }
        }
    }

    // Poll only the monotonic getter while a lookup is live; lookupDetailsChanged freezes it.
    Timer {
        interval: 250
        repeat: true
        running: root.active && root.visible && Lyrics.loading
        triggeredOnStart: true
        onTriggered: root.syncElapsed()
    }

    Connections {
        function onLookupDetailsChanged(): void {
            root.syncElapsed();
        }

        target: Lyrics
    }
}
