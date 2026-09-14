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
    readonly property var addOptions: applications.filter(app => config.pinned.indexOf(app.id) === -1)
        .map(app => ({label: app.name, value: app.id})).sort((a, b) => a.label.localeCompare(b.label))
    readonly property var screenOptions: {
        const options = [{label: qsTr("所有屏幕"), value: ""}];
        Quickshell.screens.forEach(screen => options.push({label: screen.name, value: screen.name}));
        if (config.output && !options.some(option => option.value === config.output))
            options.push({label: config.output + qsTr("（未连接）"), value: config.output});
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
    onPresentationActiveChanged: if (presentationActive) DockSettingsService.refresh()

    ColumnLayout {
        id: contentColumn
        width: Math.min(640, Math.max(0, root.width - Metrics.pageMargin * 2))
        x: Math.max(Metrics.pageMargin, (root.width - width) / 2)
        y: Metrics.pageMargin
        spacing: Metrics.spacingL

        InlineStatusBanner {
            Layout.fillWidth: true
            message: DockSettingsService.busy ? qsTr("正在同步 Dock 设置…") : qsTr("调整后自动保存并立即生效")
        }
        InlineStatusBanner {
            Layout.fillWidth: true
            visible: DockSettingsService.error !== ""
            tone: "error"
            message: DockSettingsService.error
        }
        RowLayout {
            visible: DockSettingsService.error !== ""
            ActionButton { text: qsTr("重试"); enabled: !DockSettingsService.busy; onClicked: DockSettingsService.retry() }
            ActionButton { text: qsTr("启动 Dock"); enabled: !DockSettingsService.busy; onClicked: DockSettingsService.startDock() }
        }

        SettingsSection {
            Layout.fillWidth: true
            enabled: DockSettingsService.ready
            title: qsTr("显示与隐藏")
            iconName: "dock_to_bottom"
            SettingsRow {
                Layout.fillWidth: true
                title: qsTr("显示下方 Dock")
                supportingText: qsTr("关闭后仍可从此页面重新开启。")
                trailing: StyledSwitch {
                    objectName: "dockEnabledSwitch"
                    checked: root.config.enabled !== false
                    Accessible.name: qsTr("显示下方 Dock")
                    onToggled: DockSettingsService.setOptions({enabled: checked})
                }
            }
            SettingsRow {
                Layout.fillWidth: true
                title: qsTr("显示屏幕")
                supportingText: qsTr("指定屏幕断开后，临时显示在可用屏幕上。")
                trailing: SearchSelectMenuField {
                    objectName: "dockOutputField"
                    implicitWidth: 180
                    options: root.screenOptions
                    value: root.config.output || ""
                    closeOnAccept: true
                    onAccepted: value => DockSettingsService.setOptions({output: value})
                }
            }
            SettingsRow {
                Layout.fillWidth: true
                title: qsTr("隐藏方式")
                supportingText: qsTr("智能隐藏：当前桌面有窗口时隐藏；鼠标移到屏幕底部可唤出。")
                trailing: SearchSelectMenuField {
                    objectName: "dockHideModeField"
                    implicitWidth: 180
                    options: [{label: qsTr("始终显示"), value: "always"},
                              {label: qsTr("智能隐藏"), value: "smart"},
                              {label: qsTr("自动隐藏"), value: "auto"}]
                    value: root.config.hideMode || "smart"
                    closeOnAccept: true
                    onAccepted: value => DockSettingsService.setOptions({hideMode: value})
                }
            }
            GeneralSliderSetting {
                objectName: "dockHideDelaySlider"
                enabled: root.config.hideMode !== "always"
                title: qsTr("收起等待时间")
                description: qsTr("鼠标离开 Dock 后，等待多久再收起。")
                from: 100; to: 2000; stepSize: 50; suffix: qsTr(" 毫秒")
                value: root.config.hideDelay === undefined ? 650 : root.config.hideDelay
                onMoved: value => DockSettingsService.setOptions({hideDelay: value})
            }
        }

        SettingsSection {
            Layout.fillWidth: true
            enabled: DockSettingsService.ready
            title: qsTr("大小与外观")
            iconName: "palette"
            supportingText: qsTr("颜色自动跟随系统主题；背景不透明度可单独调整。")
            Repeater {
                model: [{key: "iconSize", title: qsTr("图标大小"), from: 28, to: 64, initial: 44, suffix: qsTr(" 像素")},
                        {key: "spacing", title: qsTr("图标间距"), from: 0, to: 20, initial: 8, suffix: qsTr(" 像素")},
                        {key: "bottomMargin", title: qsTr("距屏幕底部"), from: 0, to: 32, initial: 10, suffix: qsTr(" 像素")},
                        {key: "backgroundOpacity", title: qsTr("背景不透明度"), from: 40, to: 100, initial: 93, suffix: "%"},
                        {key: "cornerRadius", title: qsTr("圆角大小"), from: 0, to: 32, initial: 20, suffix: qsTr(" 像素")}]
                GeneralSliderSetting {
                    required property var modelData
                    objectName: "dock-" + modelData.key
                    title: modelData.title
                    from: modelData.from; to: modelData.to; stepSize: 1
                    suffix: modelData.suffix
                    value: root.config[modelData.key] === undefined ? modelData.initial : root.config[modelData.key]
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
            title: qsTr("交互与提示")
            iconName: "touch_app"
            Repeater {
                model: [{key: "hoverZoom", title: qsTr("悬停时放大图标"), description: qsTr("鼠标经过图标时显示放大动画。")},
                        {key: "showTooltips", title: qsTr("显示应用名称提示"), description: qsTr("悬停时显示应用名称和固定状态。")},
                        {key: "showIndicators", title: qsTr("显示运行状态"), description: qsTr("显示运行标记、当前焦点和窗口数量。")},
                        {key: "showRunning", title: qsTr("显示未固定的运行中应用"), description: qsTr("关闭后 Dock 只显示固定应用和应用菜单。") }]
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
            title: qsTr("固定应用")
            iconName: "push_pin"
            supportingText: qsTr("顺序对应 Dock 从左到右的排列。移除固定不会卸载或关闭应用；也可以在 Dock 上右键切换固定。")
            SettingsRow {
                Layout.fillWidth: true
                title: qsTr("添加固定应用")
                trailing: SearchSelectMenuField {
                    objectName: "dockAddPinnedApp"
                    implicitWidth: 240
                    options: root.addOptions
                    placeholder: qsTr("搜索并选择应用")
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
                            accessibleName: qsTr("前移 %1").arg(pinnedRow.title)
                            enabled: pinnedRow.index > 0
                            onClicked: DockSettingsService.movePin(pinnedRow.index, -1)
                        }
                        IconButton {
                            iconName: "arrow_downward"
                            accessibleName: qsTr("后移 %1").arg(pinnedRow.title)
                            enabled: pinnedRow.index < root.config.pinned.length - 1
                            onClicked: DockSettingsService.movePin(pinnedRow.index, 1)
                        }
                        IconButton {
                            iconName: "close"
                            accessibleName: qsTr("取消固定 %1").arg(pinnedRow.title)
                            onClicked: DockSettingsService.unpin(pinnedRow.modelData)
                        }
                    }
                }
            }
            Text {
                Layout.fillWidth: true
                visible: root.config.pinned.length === 0
                text: qsTr("尚未固定应用，可在上方添加。")
                color: Appearance.colors.colOnSurfaceVariant
                font.pixelSize: 13
                wrapMode: Text.Wrap
            }
        }

        SettingsSection {
            Layout.fillWidth: true
            enabled: DockSettingsService.ready
            title: qsTr("隐藏的运行中应用")
            iconName: "visibility_off"
            supportingText: qsTr("这些应用运行时不会自动加入 Dock，但仍可手动固定。")
            SettingsRow {
                Layout.fillWidth: true
                title: qsTr("添加隐藏应用")
                trailing: SearchSelectMenuField {
                    implicitWidth: 240
                    options: root.applications.filter(app => root.config.ignoredApps.indexOf(app.id) === -1)
                        .map(app => ({label: app.name, value: app.id})).sort((a, b) => a.label.localeCompare(b.label))
                    placeholder: qsTr("搜索并选择应用")
                    closeOnAccept: true
                    onAccepted: value => DockSettingsService.setOptions({ignoredApps: root.config.ignoredApps.concat([value])})
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
                        accessibleName: qsTr("不再隐藏 %1").arg(ignoredRow.title)
                        onClicked: DockSettingsService.setOptions({ignoredApps: root.config.ignoredApps.filter(id => id !== ignoredRow.modelData)})
                    }
                }
            }
        }

        SettingsSection {
            Layout.fillWidth: true
            enabled: DockSettingsService.ready
            title: qsTr("恢复默认")
            supportingText: qsTr("恢复显示、外观与交互设置，保留固定应用的顺序和隐藏应用列表。")
            ActionButton {
                text: qsTr("恢复外观与行为默认值")
                iconName: "restart_alt"
                onClicked: DockSettingsService.resetAppearance()
            }
        }
    }
}
