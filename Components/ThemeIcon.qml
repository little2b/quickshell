import QtQuick
import qs.Services

Image {
    id: root

    property url iconSource: ""
    property bool cacheThemeIcons: false
    readonly property int themeRevision: ThemeService.iconThemeRevision
    property bool refreshing: false

    source: refreshing ? "" : cacheThemeIcons && iconSource.toString().startsWith("image://icon/")
                         ? iconSource.toString() + "#theme-" + encodeURIComponent(ThemeService.iconThemeName)
                           + "-" + themeRevision : iconSource
    // Version cached theme icons without changing the provider lookup. Other
    // consumers keep the existing uncached reload behavior on theme changes.
    cache: cacheThemeIcons || !iconSource.toString().startsWith("image://icon/")
    onThemeRevisionChanged: {
        if (cacheThemeIcons || !iconSource.toString().startsWith("image://icon/"))
            return;
        refreshing = true;
        Qt.callLater(() => root.refreshing = false);
    }
}
