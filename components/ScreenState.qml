import Quickshell
import Caelestia.Config

PersistentProperties {
    required property ShellScreen modelData

    // Drawer visibilities
    property bool bar
    property bool osd
    property bool session
    property bool launcher
    property bool dashboard
    property bool utilities
    property bool sidebar

    // Dashboard state
    property int dashboardTab
    property date dashboardDate: new Date()
    property bool chatTabPinned

    // Chat is always the last dashboard tab; derive its index from the tabs
    // enabled before it.
    readonly property int chatTabIndex: {
        let index = 0;
        if (GlobalConfig.dashboard.showDashboard)
            index++;
        if (GlobalConfig.dashboard.showMedia)
            index++;
        if (GlobalConfig.dashboard.showPerformance)
            index++;
        if (GlobalConfig.dashboard.showWeather)
            index++;
        return index;
    }
}
