import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets.common

StyledFlickable {
    id: root
    objectName: "dockSettingsPage"
    property bool presentationActive: false
    readonly property var config: DockSettingsService.settings
    readonly property var applications: DesktopEntries.applications.values.filter(app => !app.noDisplay)
    readonly property var addOptions: applications.filter(app => config.pinned.indexOf(app.id) === -1).map(
                                          app => ({
                                              label: app.name,
                                              value: app.id
                                          })).sort((a, b) => a.label.localeCompare(b.label))
    readonly property var screenOptions: {
        const options = [
                  {
                      label: qsTr("All displays"),
                      value: ""
                  }
              ];
        Quickshell.screens.forEach(screen => options.push({
                                                              label: screen.name,
                                                              value: screen.name
                                                          }));
        if (config.output && !options.some(option => option.value === config.output))
            options.push({
                             label: config.output + qsTr(" (disconnected)"),
                             value: config.output
                         });
        return options;
    }
    function appName(id) {
        const app = applications.find(app => app.id === id) || DesktopEntries.heuristicLookup(id);
        return app ? app.name : id;
    }
    clip: true
    contentWidth: width
    contentHeight: contentColumn.implicitHeight + Metrics.pageMargin * 2
    Component.onCompleted: DockSettingsService.refresh()
    onPresentationActiveChanged: if (presentationActive)
                                     DockSettingsService.refresh()

    ColumnLayout {
        id: contentColumn
        width: Math.min(640, Math.max(0, root.width - Metrics.pageMargin * 2))
        x: Math.max(Metrics.pageMargin, (root.width - width) / 2)
        y: Metrics.pageMargin
        spacing: Metrics.spacingL

        InlineStatusBanner {
            Layout.fillWidth: true
            message: DockSettingsService.busy ? qsTr("Syncing Dock settings…") : qsTr(
                                                    "Changes are saved and applied automatically")
        }
        InlineStatusBanner {
            Layout.fillWidth: true
            visible: DockSettingsService.error !== ""
            tone: "error"
            message: DockSettingsService.error
        }
        RowLayout {
            visible: DockSettingsService.error !== ""
            ActionButton {
                text: qsTr("Retry")
                enabled: !DockSettingsService.busy
                onClicked: DockSettingsService.retry()
            }
            ActionButton {
                text: qsTr("Start Dock")
                enabled: !DockSettingsService.busy
                onClicked: DockSettingsService.startDock()
            }
        }

        SettingsSection {
            Layout.fillWidth: true
            enabled: DockSettingsService.ready
            title: qsTr("Visibility")
            iconName: "dock_to_bottom"
            SettingsRow {
                Layout.fillWidth: true
                title: qsTr("Show bottom Dock")
                supportingText: qsTr("You can enable the Dock again from this page.")
                trailing: StyledSwitch {
                    objectName: "dockEnabledSwitch"
                    checked: root.config.enabled !== false
                    Accessible.name: qsTr("Show bottom Dock")
                    onToggled: DockSettingsService.setOptions({
                                                                  enabled: checked
                                                              })
                }
            }
            SettingsRow {
                Layout.fillWidth: true
                title: qsTr("Display")
                supportingText: qsTr("Use an available display while the selected display is disconnected.")
                trailing: SearchSelectMenuField {
                    objectName: "dockOutputField"
                    implicitWidth: 180
                    options: root.screenOptions
                    value: root.config.output || ""
                    closeOnAccept: true
                    onAccepted: value => DockSettingsService.setOptions({
                                                                            output: value
                                                                        })
                }
            }
            SettingsRow {
                Layout.fillWidth: true
                title: qsTr("Visibility mode")
                supportingText: qsTr(
                                    "Intelligent hiding hides the Dock when the current workspace has windows. Move the pointer to the bottom edge to reveal it.")
                trailing: SearchSelectMenuField {
                    objectName: "dockHideModeField"
                    implicitWidth: 180
                    options: [
                        {
                            label: qsTr("Always visible"),
                            value: "always"
                        },
                        {
                            label: qsTr("Intelligent hiding"),
                            value: "smart"
                        },
                        {
                            label: qsTr("Auto-hide"),
                            value: "auto"
                        }
                    ]
                    value: root.config.hideMode || "smart"
                    closeOnAccept: true
                    onAccepted: value => DockSettingsService.setOptions({
                                                                            hideMode: value
                                                                        })
                }
            }
            GeneralSliderSetting {
                objectName: "dockHideDelaySlider"
                enabled: root.config.hideMode !== "always"
                title: qsTr("Hide delay")
                description: qsTr("How long to wait before hiding after the pointer leaves the Dock.")
                from: 100
                to: 2000
                stepSize: 50
                suffix: qsTr(" ms")
                value: root.config.hideDelay === undefined ? 650 : root.config.hideDelay
                onMoved: value => DockSettingsService.setOptions({
                                                                     hideDelay: value
                                                                 })
            }
        }

        SettingsSection {
            Layout.fillWidth: true
            enabled: DockSettingsService.ready
            title: qsTr("Size and appearance")
            iconName: "palette"
            supportingText: qsTr(
                                "Colors follow the system theme. Background opacity can be adjusted separately.")
            Repeater {
                model: [
                    {
                        key: "iconSize",
                        title: qsTr("Icon size"),
                        from: 28,
                        to: 64,
                        initial: 44,
                        suffix: qsTr(" px")
                    },
                    {
                        key: "spacing",
                        title: qsTr("Icon spacing"),
                        from: 0,
                        to: 20,
                        initial: 8,
                        suffix: qsTr(" px")
                    },
                    {
                        key: "bottomMargin",
                        title: qsTr("Bottom margin"),
                        from: 0,
                        to: 32,
                        initial: 10,
                        suffix: qsTr(" px")
                    },
                    {
                        key: "backgroundOpacity",
                        title: qsTr("Background opacity"),
                        from: 40,
                        to: 100,
                        initial: 93,
                        suffix: "%"
                    },
                    {
                        key: "cornerRadius",
                        title: qsTr("Corner radius"),
                        from: 0,
                        to: 32,
                        initial: 20,
                        suffix: qsTr(" px")
                    }
                ]
                GeneralSliderSetting {
                    required property var modelData
                    objectName: "dock-" + modelData.key
                    title: modelData.title
                    from: modelData.from
                    to: modelData.to
                    stepSize: 1
                    suffix: modelData.suffix
                    value: root.config[modelData.key] === undefined ? modelData.initial :
                                                                      root.config[modelData.key]
                    onMoved: value => {
                        const patch = {};
                        patch[modelData.key] = value;
                        DockSettingsService.setOptions(patch);
                    }
                }
            }
        }

        SettingsSection {
            Layout.fillWidth: true
            enabled: DockSettingsService.ready
            title: qsTr("Interaction and tooltips")
            iconName: "touch_app"
            Repeater {
                model: [
                    {
                        key: "hoverZoom",
                        title: qsTr("Magnify icons on hover"),
                        description: qsTr("Animate icon magnification when the pointer moves over an icon.")
                    },
                    {
                        key: "showTooltips",
                        title: qsTr("Show application tooltips"),
                        description: qsTr("Show the application name and pinned status on hover.")
                    },
                    {
                        key: "showIndicators",
                        title: qsTr("Show running status"),
                        description: qsTr("Show running indicators, focus and window counts.")
                    },
                    {
                        key: "showRunning",
                        title: qsTr("Show unpinned running applications"),
                        description: qsTr(
                                         "When disabled, show only pinned applications and the application menu.")
                    }
                ]
                SettingsRow {
                    id: toggleRow
                    required property var modelData
                    Layout.fillWidth: true
                    title: modelData.title
                    supportingText: modelData.description
                    trailing: StyledSwitch {
                        objectName: "dock-" + toggleRow.modelData.key
                        checked: root.config[toggleRow.modelData.key] !== false
                        Accessible.name: toggleRow.title
                        onToggled: {
                            const patch = {};
                            patch[toggleRow.modelData.key] = checked;
                            DockSettingsService.setOptions(patch);
                        }
                    }
                }
            }
        }

        SettingsSection {
            Layout.fillWidth: true
            enabled: DockSettingsService.ready
            title: qsTr("Pinned applications")
            iconName: "push_pin"
            supportingText: qsTr(
                                "Applications appear from left to right in this order. Unpinning does not uninstall or close an application. You can also right-click a Dock icon to pin or unpin it.")
            SettingsRow {
                Layout.fillWidth: true
                title: qsTr("Pin an application")
                trailing: SearchSelectMenuField {
                    objectName: "dockAddPinnedApp"
                    implicitWidth: 240
                    options: root.addOptions
                    placeholder: qsTr("Search and select an application")
                    closeOnAccept: true
                    onAccepted: value => DockSettingsService.pin(value)
                }
            }
            Repeater {
                model: root.config.pinned
                SettingsRow {
                    id: pinnedRow
                    required property string modelData
                    required property int index
                    Layout.fillWidth: true
                    title: root.appName(modelData)
                    supportingText: modelData
                    trailing: RowLayout {
                        spacing: 0
                        IconButton {
                            iconName: "arrow_upward"
                            accessibleName: qsTr("Move %1 earlier").arg(pinnedRow.title)
                            enabled: pinnedRow.index > 0
                            onClicked: DockSettingsService.movePin(pinnedRow.index, -1)
                        }
                        IconButton {
                            iconName: "arrow_downward"
                            accessibleName: qsTr("Move %1 later").arg(pinnedRow.title)
                            enabled: pinnedRow.index < root.config.pinned.length - 1
                            onClicked: DockSettingsService.movePin(pinnedRow.index, 1)
                        }
                        IconButton {
                            iconName: "close"
                            accessibleName: qsTr("Unpin %1").arg(pinnedRow.title)
                            onClicked: DockSettingsService.unpin(pinnedRow.modelData)
                        }
                    }
                }
            }
            Text {
                Layout.fillWidth: true
                visible: root.config.pinned.length === 0
                text: qsTr("No pinned applications. Add one above.")
                color: Appearance.colors.colOnSurfaceVariant
                font.pixelSize: 13
                wrapMode: Text.Wrap
            }
        }

        SettingsSection {
            Layout.fillWidth: true
            enabled: DockSettingsService.ready
            title: qsTr("Hidden running applications")
            iconName: "visibility_off"
            supportingText: qsTr(
                                "These applications are not added automatically while running, but can still be pinned manually.")
            SettingsRow {
                Layout.fillWidth: true
                title: qsTr("Hide an application")
                trailing: SearchSelectMenuField {
                    implicitWidth: 240
                    options: root.applications.filter(app => root.config.ignoredApps.indexOf(app.id) === -1).map(
                                 app => ({
                                     label: app.name,
                                     value: app.id
                                 })).sort((a, b) => a.label.localeCompare(b.label))
                    placeholder: qsTr("Search and select an application")
                    closeOnAccept: true
                    onAccepted: value => DockSettingsService.setOptions({
                                                                            ignoredApps:
                                                                            root.config.ignoredApps.concat(
                                                                                [value])
                                                                        })
                }
            }
            Repeater {
                model: root.config.ignoredApps
                SettingsRow {
                    id: ignoredRow
                    required property string modelData
                    Layout.fillWidth: true
                    title: root.appName(modelData)
                    supportingText: modelData
                    trailing: IconButton {
                        iconName: "close"
                        accessibleName: qsTr("Unhide %1").arg(ignoredRow.title)
                        onClicked: DockSettingsService.setOptions({
                                                                      ignoredApps:
                                                                      root.config.ignoredApps.filter(id => id
                                                                                                           !== ignoredRow.modelData)
                                                                  })
                    }
                }
            }
        }

        SettingsSection {
            Layout.fillWidth: true
            enabled: DockSettingsService.ready
            title: qsTr("Restore defaults")
            supportingText: qsTr(
                                "Reset visibility, appearance and interaction settings while keeping pinned order and hidden applications.")
            ActionButton {
                text: qsTr("Reset appearance and behavior")
                iconName: "restart_alt"
                onClicked: DockSettingsService.resetAppearance()
            }
        }
    }
}
