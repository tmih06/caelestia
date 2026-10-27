pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.filedialog

Item {
    id: root

    required property ScreenState screenState
    required property FileDialog facePicker
    property bool sharedMedia: false
    property bool animatePages: true
    property real viewportWidth: width
    property real viewportHeight: height

    readonly property alias tabPosition: view.tabPosition
    readonly property alias mediaPageOffset: view.mediaPageOffset
    readonly property rect pageViewport: Qt.rect(viewWrapper.x, viewWrapper.y, view.width, view.height)
    readonly property bool switchingTabs: view ? Math.abs(view.contentX - (view.currentItem?.x ?? 0)) > 0.5 : false

    // The content tree stays loaded while the compact media dock needs morph
    // targets, so pages must gate their animations on actual on-screen state
    // rather than their own visible/enabled properties.
    readonly property bool contentActive: root.screenState.dashboard

    readonly property var dashboardTabs: {
        const allTabs = [
            {
                id: "dashboard",
                component: dashComponent,
                iconName: "dashboard",
                text: Tr.tr("Dashboard"),
                enabled: Config.dashboard.showDashboard
            },
            {
                id: "media",
                component: mediaComponent,
                iconName: "queue_music",
                text: Tr.tr("Media"),
                enabled: Config.dashboard.showMedia
            },
            {
                id: "performance",
                component: performanceComponent,
                iconName: "speed",
                text: Tr.tr("Performance"),
                enabled: Config.dashboard.showPerformance
            },
            {
                id: "weather",
                component: weatherComponent,
                iconName: "cloud",
                text: Tr.tr("Weather"),
                enabled: Config.dashboard.showWeather
            }
        ];
        return allTabs.filter(tab => tab.enabled);
    }

    readonly property real nonAnimWidth: view.implicitWidth + viewWrapper.anchors.margins * 2
    readonly property real nonAnimHeight: tabs.implicitHeight + tabs.anchors.topMargin + view.implicitHeight + viewWrapper.anchors.margins * 2

    function tabActive(id: string): bool {
        return root.contentActive && root.dashboardTabs[view.currentIndex]?.id === id;
    }

    function mediaTargetRect(item: Item): rect {
        const pos = item.mapToItem(root, 0, 0);
        // Targets are measured in the Media page's settled coordinate system.
        return Qt.rect(pos.x - root.mediaPageOffset, pos.y, item.width, item.height);
    }

    implicitWidth: nonAnimWidth
    implicitHeight: nonAnimHeight

    Tabs {
        id: tabs

        anchors.top: parent.top
        anchors.left: parent.left
        width: Math.max(0, root.viewportWidth - anchors.margins * 2)
        anchors.topMargin: CUtils.clamp(anchors.margins - Config.border.thickness, 0, anchors.margins)
        anchors.margins: Tokens.padding.large

        position: root.tabPosition
        screenState: root.screenState
        tabs: root.dashboardTabs
    }

    Item {
        id: viewWrapper

        anchors.top: tabs.bottom
        anchors.left: parent.left
        width: Math.max(0, root.viewportWidth - anchors.margins * 2)
        height: Math.max(0, root.viewportHeight - y - anchors.margins)
        anchors.margins: Tokens.padding.large

        clip: true

        Item {
            id: view

            readonly property int currentIndex: root.screenState.dashboardTab
            property real contentX: currentItem?.x ?? 0
            property real dragOrigin: 0
            readonly property Item currentItem: {
                CUtils.dependency(repeater.count); // Trigger update on count change
                return repeater.itemAt(currentIndex);
            }
            readonly property Item mediaPane: {
                CUtils.dependency(repeater?.count ?? 0);
                const index = root.dashboardTabs.findIndex(tab => tab.id === "media");
                return index >= 0 ? repeater?.itemAt(index) ?? null : null;
            }
            readonly property real mediaPageOffset: (mediaPane?.x ?? 0) - contentX
            readonly property real tabPosition: {
                CUtils.dependency(repeater?.count ?? 0);
                const count = repeater?.count ?? 0;
                for (let index = count - 1; index >= 0; --index) {
                    const page = repeater.itemAt(index);
                    if (page && contentX >= page.x) {
                        const next = repeater.itemAt(index + 1);
                        if (next)
                            return index + (contentX - page.x) / Math.max(1, next.x - page.x);
                        const previous = repeater.itemAt(index - 1);
                        return previous ? index + (contentX - page.x) / Math.max(1, page.x - previous.x) : index;
                    }
                }
                const first = repeater?.itemAt(0);
                const second = repeater?.itemAt(1);
                return first && second ? (contentX - first.x) / Math.max(1, second.x - first.x) : 0;
            }

            function moveTo(value: real): void {
                contentX = Math.max(0, Math.min(value, repeater.itemAt(repeater.count - 1)?.x ?? 0));
            }

            function settle(): void {
                if (!currentItem)
                    return;
                let nearest = currentIndex;
                let distance = Infinity;
                for (let index = 0; index < repeater.count; index++) {
                    const delta = Math.abs(contentX - repeater.itemAt(index).x);
                    if (delta < distance) {
                        nearest = index;
                        distance = delta;
                    }
                }
                const offset = contentX - currentItem.x;
                if (nearest === currentIndex && Math.abs(offset) > currentItem.width / 10)
                    nearest = Math.max(0, Math.min(currentIndex + (offset > 0 ? 1 : -1), repeater.count - 1));
                root.screenState.dashboardTab = nearest;
                contentX = Qt.binding(() => currentItem?.x ?? 0);
            }

            anchors.fill: parent

            objectName: "dashboardPager"

            implicitWidth: currentItem?.implicitWidth ?? 0
            implicitHeight: currentItem?.implicitHeight ?? 0

            DragHandler {
                id: drag

                target: null
                yAxis.enabled: false
                onActiveChanged: {
                    if (active)
                        view.dragOrigin = view.contentX;
                    else
                        view.settle();
                }
                onActiveTranslationChanged: {
                    if (active)
                        view.moveTo(view.dragOrigin - activeTranslation.x);
                }
            }

            WheelHandler {
                id: wheel

                target: null
                orientation: Qt.Horizontal
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onActiveChanged: {
                    if (!active)
                        view.settle();
                }
                onWheel: event => {
                    const delta = event.pixelDelta.x || event.angleDelta.x;
                    if (!delta) {
                        event.accepted = false;
                        return;
                    }
                    view.moveTo(view.contentX - delta);
                    event.accepted = true;
                }
            }

            Row {
                id: row

                x: -view.contentX
                spacing: 5

                Repeater {
                    id: repeater

                    model: ScriptModel {
                        values: root.dashboardTabs
                    }

                    delegate: Loader {
                        id: paneLoader

                        required property int index
                        required property var modelData

                        sourceComponent: modelData.component
                        asynchronous: true
                        // Keep positioners measurable; zero opacity culls offscreen rendering.
                        opacity: index === view.currentIndex || (x < view.contentX + view.width && x + width > view.contentX) ? 1 : 0
                        enabled: index === view.currentIndex

                        Binding {
                            target: paneLoader.item
                            property: "enabled"
                            when: paneLoader.item !== null
                            value: paneLoader.enabled && root.contentActive
                        }
                    }
                }
            }

            Component {
                id: dashComponent

                Dash {
                    screenState: root.screenState
                    facePicker: root.facePicker
                    pageActive: root.tabActive("dashboard")
                }
            }

            Component {
                id: mediaComponent

                Media {
                    screenState: root.screenState
                    sharedMedia: root.sharedMedia
                    pageActive: root.tabActive("media")
                    animateBackground: root.animatePages && !root.switchingTabs && view.mediaPageOffset < view.width && view.mediaPageOffset + (view.mediaPane?.width ?? 0) > 0
                }
            }

            Component {
                id: performanceComponent

                Performance {
                    pageActive: root.tabActive("performance")
                }
            }

            Component {
                id: weatherComponent

                WeatherTab {}
            }

            Behavior on contentX {
                enabled: !drag.active && !wheel.active

                Anim {
                    type: Anim.DefaultSpatial
                }
            }
        }
    }
}
