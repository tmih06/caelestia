pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Caelestia.Config
import qs.components
import qs.services
import qs.modules.clipboard

Singleton {
    id: root

    property var currentWindow: null

    function open(): void {
        if (!currentWindow) {
            currentWindow = winComp.createObject(dummy);
        } else {
            currentWindow.requestActivate();
        }
    }

    function close(): void {
        if (currentWindow) {
            currentWindow.destroy();
            currentWindow = null;
        }
    }

    function toggle(): void {
        if (currentWindow) {
            close();
        } else {
            open();
        }
    }

    QtObject {
        id: dummy
    }

    Component {
        id: winComp

        FloatingWindow {
            id: win

            color: Colours.tPalette.m3surface
            surfaceFormat.opaque: false

            implicitWidth: 940
            implicitHeight: 580

            minimumSize.width: 720
            minimumSize.height: 440

            title: Tr.tr("Clipboard")

            onVisibleChanged: {
                if (!visible) {
                    win.destroy();
                    root.currentWindow = null;
                }
            }

            HyprlandFocusGrab {
                id: grab
                active: false
                windows: [win]
                onCleared: root.close()
            }

            Timer {
                id: grabTimer
                interval: 200
                running: true
                onTriggered: grab.active = true
            }
            Connections {
                target: Hypr

                function onActiveWsIdChanged(): void {
                    root.close();
                }
            }

            Behavior on color {
                CAnim {}
            }

            Clipboard {
                anchors.fill: parent
                onCloseRequested: {
                    win.destroy();
                    root.currentWindow = null;
                }
            }
        }
    }
}
