pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.components.containers
import qs.services

Item {
    id: root

    readonly property string helperPath: Quickshell.shellPath("modules/clipboard/clipboard-helper.py")

    signal closeRequested

    implicitWidth: 940
    implicitHeight: 580

    property var allItems: []
    property int selectedIndex: 0
    property var currentItem: filteredModel.count > selectedIndex && selectedIndex >= 0 ? filteredModel.get(selectedIndex) : null
    property string currentImageSource: ""
    property string currentTextContent: ""

    ListModel {
        id: filteredModel
    }

    // Process to list clipboard entries
    Process {
        id: listProc

        command: ["python3", root.helperPath, "list", "150"]

        stdout: StdioCollector {
            onStreamFinished: {
                if (!text || text.trim().length === 0)
                    return;
                try {
                    const parsed = JSON.parse(text);
                    root.allItems = parsed;
                    root.applyFilter(searchBar.text);
                } catch (e) {
                    console.warn("Failed to parse clipboard list:", e, text);
                }
            }
        }
    }

    // Process to decode on-demand image
    Process {
        id: decodeProc

        property string pendingId: ""
        property string runningId: ""

        command: ["python3", root.helperPath, "decode", pendingId]

        onRunningChanged: {
            if (running)
                runningId = pendingId;
        }

        stdout: StdioCollector {
            onStreamFinished: {
                if (decodeProc.runningId !== decodeProc.pendingId) {
                    // Selection changed while decoding; discard stale result and restart
                    decodeProc.running = true;
                    return;
                }
                const path = text.trim();
                if (path.length > 0) {
                    root.currentImageSource = "file://" + path;
                }
            }
        }
    }

    // Process to fetch full text if needed
    Process {
        id: textProc

        property string pendingId: ""
        property string runningId: ""

        command: ["python3", root.helperPath, "get-text", pendingId]

        onRunningChanged: {
            if (running)
                runningId = pendingId;
        }

        stdout: StdioCollector {
            onStreamFinished: {
                if (textProc.runningId !== textProc.pendingId) {
                    // Selection changed while fetching; discard stale result and restart
                    textProc.running = true;
                    return;
                }
                root.currentTextContent = text;
            }
        }
    }

    function refresh(): void {
        listProc.running = true;
    }

    function applyFilter(query: string): void {
        filteredModel.clear();
        const q = (query || "").toLowerCase();

        for (let i = 0; i < root.allItems.length; i++) {
            const item = root.allItems[i];
            const target = (item.preview || "").toLowerCase();
            if (q.length === 0 || target.includes(q)) {
                filteredModel.append(item);
            }
        }

        if (filteredModel.count > 0) {
            root.selectedIndex = 0;
            root.updatePreview();
        } else {
            root.selectedIndex = -1;
            root.currentImageSource = "";
            root.currentTextContent = "";
        }
    }

    function updatePreview(): void {
        const item = root.currentItem;
        if (!item) {
            root.currentImageSource = "";
            root.currentTextContent = "";
            return;
        }

        if (item.isImage) {
            root.currentTextContent = "";
            decodeProc.pendingId = item.id;
            if (!decodeProc.running)
                decodeProc.running = true;
        } else {
            root.currentImageSource = "";
            root.currentTextContent = item.preview || "";
            textProc.pendingId = item.id;
            if (!textProc.running)
                textProc.running = true;
        }
    }

    function copyCurrent(): void {
        const item = root.currentItem;
        if (!item)
            return;
        Quickshell.execDetached(["python3", root.helperPath, "copy", item.id]);
        root.closeRequested();
    }

    function deleteCurrent(): void {
        const item = root.currentItem;
        if (!item)
            return;
        Quickshell.execDetached(["python3", root.helperPath, "delete", item.id]);

        // Remove from local allItems
        root.allItems = root.allItems.filter(x => x.id !== item.id);
        root.applyFilter(searchBar.text);
    }

    function moveSelection(delta: int): void {
        if (filteredModel.count === 0)
            return;
        root.selectedIndex = Math.max(0, Math.min(root.selectedIndex + delta, filteredModel.count - 1));
        listView.positionViewAtIndex(root.selectedIndex, ListView.Contain);
        root.updatePreview();
    }

    Component.onCompleted: {
        root.refresh();
        Qt.callLater(() => searchBar.forceActiveFocus());
    }

    // Outer Background
    StyledRect {
        id: bg

        anchors.fill: parent
        color: Colours.tPalette.m3surface
        radius: Tokens.rounding.large
        border.color: Colours.tPalette.m3outlineVariant
        border.width: 1

        // Left Panel (Compact List & Search)
        Item {
            id: leftPanel

            width: 380
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.margins: Tokens.padding.medium

            // Search Bar
            SearchBar {
                id: searchBar

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                placeholderText: Tr.tr("Search clipboard...")

                onTextChanged: root.applyFilter(text)

                Keys.onDownPressed: event => {
                    root.moveSelection(1);
                    event.accepted = true;
                }

                Keys.onUpPressed: event => {
                    root.moveSelection(-1);
                    event.accepted = true;
                }

                Keys.onReturnPressed: event => {
                    root.copyCurrent();
                    event.accepted = true;
                }

                Keys.onEnterPressed: event => {
                    root.copyCurrent();
                    event.accepted = true;
                }

                Keys.onEscapePressed: event => {
                    root.closeRequested();
                    event.accepted = true;
                }
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_PageDown) {
                        root.moveSelection(8);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_PageUp) {
                        root.moveSelection(-8);
                        event.accepted = true;
                    }
                }
                Keys.onDeletePressed: event => {
                    root.deleteCurrent();
                    event.accepted = true;
                }
            }

            // Compact List
            StyledListView {
                id: listView

                anchors.top: searchBar.bottom
                anchors.topMargin: Tokens.spacing.small
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                clip: true

                model: filteredModel
                currentIndex: root.selectedIndex

                delegate: Item {
                    id: delegateItem

                    required property var model
                    required property int index

                    readonly property bool isSelected: index === root.selectedIndex

                    width: listView.width
                    height: 52

                    StyledRect {
                        anchors.fill: parent
                        anchors.bottomMargin: 2
                        radius: Tokens.rounding.medium
                        color: delegateItem.isSelected ? Colours.palette.m3primaryContainer : (stateLayer.containsMouse ? Colours.tPalette.m3surfaceContainerHigh : "transparent")

                        Behavior on color {
                            CAnim {}
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: Tokens.padding.small
                            spacing: Tokens.spacing.medium

                            // Icon
                            StyledRect {
                                Layout.preferredWidth: 34
                                Layout.preferredHeight: 34
                                radius: Tokens.rounding.small
                                color: delegateItem.isSelected ? Colours.palette.m3primary : Colours.tPalette.m3surfaceContainer

                                MaterialIcon {
                                    anchors.centerIn: parent
                                    text: delegateItem.model.isImage ? "image" : "content_copy"
                                    color: delegateItem.isSelected ? Colours.palette.m3onPrimary : Colours.palette.m3primary
                                    fontStyle: Tokens.font.icon.small
                                }
                            }

                            // Text Content
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                StyledText {
                                    Layout.fillWidth: true
                                    text: delegateItem.model.isImage ? (delegateItem.model.dim ? Tr.tr("Image (%1)").arg(delegateItem.model.dim) : Tr.tr("Image (%1)").arg(delegateItem.model.size)) : delegateItem.model.preview
                                    font: Tokens.font.body.small
                                    color: delegateItem.isSelected ? Colours.palette.m3onPrimaryContainer : Colours.tPalette.m3onSurface
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: delegateItem.model.isImage ? (delegateItem.model.format + " • " + delegateItem.model.size) : delegateItem.model.size
                                    font: Tokens.font.label.small
                                    color: delegateItem.isSelected ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurfaceVariant
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        StateLayer {
                            id: stateLayer

                            anchors.fill: parent
                            radius: Tokens.rounding.medium
                            onClicked: {
                                root.selectedIndex = delegateItem.index;
                                root.updatePreview();
                                searchBar.focus = true;
                            }
                            onDoubleClicked: {
                                root.selectedIndex = delegateItem.index;
                                root.copyCurrent();
                            }
                        }
                    }
                }
            }
        }

        // Vertical Divider
        StyledRect {
            id: divider

            width: 1
            anchors.left: leftPanel.right
            anchors.leftMargin: Tokens.padding.small
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.margins: Tokens.padding.medium
            color: Colours.tPalette.m3outlineVariant
        }

        // Right Panel (Live Preview)
        Item {
            id: rightPanel

            anchors.left: divider.right
            anchors.leftMargin: Tokens.padding.medium
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.margins: Tokens.padding.medium

            // Header Row (Badge + Action Buttons)
            RowLayout {
                id: previewHeader

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                spacing: Tokens.spacing.small

                // Metadata Pill Badge
                StyledRect {
                    Layout.fillWidth: true
                    implicitHeight: 36
                    radius: Tokens.rounding.full
                    color: Colours.tPalette.m3surfaceContainerHigh

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Tokens.padding.medium
                        anchors.rightMargin: Tokens.padding.medium
                        spacing: Tokens.spacing.small

                        MaterialIcon {
                            text: root.currentItem?.isImage ? "image" : "description"
                            color: Colours.palette.m3primary
                            fontStyle: Tokens.font.icon.small
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: {
                                const it = root.currentItem;
                                if (!it) return Tr.tr("No selection");
                                if (it.isImage) {
                                    return Tr.tr("%1 Image • %2 • %3").arg(it.format).arg(it.dim || Tr.tr("Unknown size")).arg(it.size);
                                }
                                const lines = (root.currentTextContent || "").split("\n").length;
                                return Tr.tr("Text • %1 lines • %2 characters").arg(lines).arg((root.currentTextContent || "").length);
                            }
                            font: Tokens.font.label.small
                            color: Colours.tPalette.m3onSurface
                            elide: Text.ElideRight
                        }
                    }
                }

                // Copy Action Button
                IconButton {
                    icon: "content_copy"
                    type: IconButton.Filled
                    enabled: root.currentItem !== null
                    onClicked: root.copyCurrent()
                }

                // Delete Action Button
                IconButton {
                    icon: "delete"
                    type: IconButton.Tonal
                    enabled: root.currentItem !== null
                    onClicked: root.deleteCurrent()
                }

                // Close Window Button
                IconButton {
                    icon: "close"
                    type: IconButton.Text
                    onClicked: root.closeRequested()
                }
            }

            // Preview Body Container
            StyledRect {
                anchors.top: previewHeader.bottom
                anchors.topMargin: Tokens.spacing.medium
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                radius: Tokens.rounding.medium
                color: Colours.tPalette.m3surfaceContainerLowest
                clip: true

                // Image Preview Mode
                Item {
                    anchors.fill: parent
                    anchors.margins: Tokens.padding.medium
                    visible: root.currentItem?.isImage ?? false

                    Image {
                        id: imgPreview

                        anchors.fill: parent
                        source: root.currentImageSource
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        mipmap: true
                        asynchronous: true

                        // Fade in on image load
                        opacity: status === Image.Ready ? 1 : 0
                        Behavior on opacity {
                            Anim {
                                type: Anim.DefaultEffects
                            }
                        }
                    }

                    // Loading indicator if image is decoding
                    StyledText {
                        anchors.centerIn: parent
                        text: Tr.tr("Loading preview...")
                        font: Tokens.font.body.medium
                        color: Colours.palette.m3outline
                        visible: imgPreview.status === Image.Loading
                    }
                }

                // Text Preview Mode
                StyledFlickable {
                    anchors.fill: parent
                    anchors.margins: Tokens.padding.medium
                    visible: !(root.currentItem?.isImage ?? false)
                    contentWidth: width
                    contentHeight: textDisplay.implicitHeight

                    StyledText {
                        id: textDisplay

                        width: parent.width
                        text: root.currentTextContent
                        font: Tokens.font.body.small
                        color: Colours.tPalette.m3onSurface
                        wrapMode: Text.WrapAnywhere
                        textFormat: Text.PlainText
                    }
                }

                // Empty State
                StyledText {
                    anchors.centerIn: parent
                    text: Tr.tr("No clipboard items found")
                    font: Tokens.font.body.medium
                    color: Colours.palette.m3outline
                    visible: filteredModel.count === 0
                }
            }
        }
    }
}
