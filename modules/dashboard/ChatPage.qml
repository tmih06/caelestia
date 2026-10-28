import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services

Item {
    id: root

    property bool pageActive: true

    signal closeRequested

    readonly property var suggestions: [Tr.tr("What's on my schedule today?"), Tr.tr("Summarize the latest news"), Tr.tr("What's the weather like?")]

    implicitWidth: Tokens.sizes.dashboard.mediaTabWidth
    implicitHeight: Tokens.sizes.dashboard.mediaTabHeight

    function submit(): void {
        const prompt = input.text.trim();
        if (!prompt || Chat.busy)
            return;

        input.text = "";
        Chat.send(prompt);
        input.forceActiveFocus();
    }

    onPageActiveChanged: {
        if (pageActive)
            Qt.callLater(input.forceActiveFocus);
    }

    Component.onCompleted: {
        if (pageActive)
            Qt.callLater(input.forceActiveFocus);
    }

    StyledRect {
        anchors.fill: parent
        color: Colours.palette.m3surfaceContainerHigh
        radius: Tokens.rounding.extraLarge
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.small

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            StyledRect {
                implicitWidth: 32
                implicitHeight: 32
                radius: Tokens.rounding.full
                color: Colours.palette.m3primaryContainer

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "smart_toy"
                    color: Colours.palette.m3onPrimaryContainer
                    fontStyle: Tokens.font.icon.builders.small.build()
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    text: "Loio"
                    font: Tokens.font.title.small
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Chat.error ? Chat.error : Chat.busy ? Tr.tr("Thinking…") : Tr.tr("Personal assistant")
                    color: Chat.error ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.label.small
                    elide: Text.ElideRight
                }
            }

            IconButton {
                icon: "delete_sweep"
                type: IconButton.Text
                disabled: Chat.busy || Chat.messages.length === 0
                onClicked: Chat.clear()
            }
        }

        StyledRect {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Qt.alpha(Colours.palette.m3outlineVariant, 0.6)
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            ListView {
                id: history

                anchors.fill: parent
                clip: true
                spacing: 2
                boundsBehavior: Flickable.StopAtBounds
                model: Chat.messages
                visible: Chat.messages.length > 0

                onCountChanged: Qt.callLater(positionViewAtEnd)

                delegate: Item {
                    id: messageRow

                    required property var modelData

                    readonly property bool fromUser: modelData.role === "user"

                    width: history.width
                    implicitHeight: messageLayout.implicitHeight + Tokens.padding.small * 2

                    RowLayout {
                        id: messageLayout

                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Tokens.spacing.small

                        StyledRect {
                            Layout.alignment: Qt.AlignTop
                            implicitWidth: 24
                            implicitHeight: 24
                            radius: Tokens.rounding.full
                            color: messageRow.fromUser ? Colours.palette.m3primaryContainer : Colours.palette.m3surfaceContainerHighest

                            MaterialIcon {
                                anchors.centerIn: parent
                                text: messageRow.fromUser ? "person" : "smart_toy"
                                color: messageRow.fromUser ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurfaceVariant
                                fontStyle: Tokens.font.icon.builders.small.build()
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            StyledText {
                                text: messageRow.fromUser ? Tr.tr("You") : "Loio"
                                color: messageRow.fromUser ? Colours.palette.m3onSurfaceVariant : Colours.palette.m3primary
                                font: Tokens.font.label.small
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: messageRow.modelData.text
                                color: Colours.palette.m3onSurface
                                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                                font: Tokens.font.body.medium
                                animate: true
                            }
                        }
                    }
                }
            }

            ColumnLayout {
                anchors.centerIn: parent
                width: Math.min(parent.width, 420)
                visible: Chat.messages.length === 0
                spacing: Tokens.spacing.extraSmall

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Tr.tr("Ask Loio anything")
                    font: Tokens.font.title.small
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.bottomMargin: Tokens.spacing.small
                    text: Tr.tr("Enter to send • Esc to close")
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.label.small
                }

                Repeater {
                    model: root.suggestions

                    StyledRect {
                        id: suggestion

                        required property string modelData

                        Layout.fillWidth: true
                        implicitHeight: suggestionRow.implicitHeight + Tokens.padding.small * 2
                        radius: Tokens.rounding.medium
                        color: suggestionArea.containsMouse ? Colours.palette.m3surfaceContainerHighest : Colours.palette.m3surfaceContainer

                        RowLayout {
                            id: suggestionRow

                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: Tokens.padding.medium
                            anchors.rightMargin: Tokens.padding.medium
                            spacing: Tokens.spacing.small

                            StyledText {
                                Layout.fillWidth: true
                                text: suggestion.modelData
                                color: Colours.palette.m3onSurfaceVariant
                                font: Tokens.font.body.small
                                elide: Text.ElideRight
                            }

                            MaterialIcon {
                                text: "north_west"
                                color: Colours.palette.m3onSurfaceVariant
                                fontStyle: Tokens.font.icon.builders.small.build()
                            }
                        }

                        MouseArea {
                            id: suggestionArea

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (!Chat.busy)
                                    Chat.send(suggestion.modelData);
                            }
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            StyledRect {
                Layout.fillWidth: true
                implicitHeight: 44
                color: Colours.palette.m3surfaceContainerHighest
                radius: Tokens.rounding.full
                border.width: 1
                border.color: input.activeFocus ? Colours.palette.m3primary : Qt.alpha(Colours.palette.m3outlineVariant, 0.6)

                TextFieldBase {
                    id: input

                    anchors.fill: parent
                    anchors.leftMargin: Tokens.padding.large
                    anchors.rightMargin: Tokens.padding.large
                    background: null
                    placeholderText: ""
                    font: Tokens.font.body.medium
                    onAccepted: root.submit()

                    Keys.onEscapePressed: {
                        if (Chat.busy)
                            Chat.cancel();
                        else
                            root.closeRequested();
                    }
                }

                StyledText {
                    anchors.left: parent.left
                    anchors.leftMargin: Tokens.padding.large
                    anchors.verticalCenter: parent.verticalCenter
                    visible: input.text.length === 0
                    text: Chat.busy ? Tr.tr("Waiting for Loio…") : Tr.tr("Message Loio…")
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.medium
                }
            }

            IconButton {
                visible: !Chat.busy
                icon: "arrow_upward"
                type: IconButton.Filled
                isRound: true
                implicitWidth: 44
                implicitHeight: 44
                disabled: input.text.trim().length === 0
                onClicked: root.submit()
            }

            IconButton {
                visible: Chat.busy
                icon: "stop"
                type: IconButton.Tonal
                isRound: true
                implicitWidth: 44
                implicitHeight: 44
                onClicked: Chat.cancel()
            }
        }
    }
}
