import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import qs.Widgets.common

StyledFlickable {
    id: root
    property bool presentationActive: false
    clip: true
    contentWidth: width
    contentHeight: contentColumn.implicitHeight + Metrics.pageMargin * 2

    Component.onCompleted: {
        NiriConfigService.refresh();
        ThemeService.detectAvailableThemes();
    }
    onPresentationActiveChanged: if (presentationActive) NiriConfigService.refresh()

    ColumnLayout {
        id: contentColumn
        width: Math.min(640, Math.max(0, root.width - Metrics.pageMargin * 2))
        x: Math.max(Metrics.pageMargin, (root.width - width) / 2)
        y: Metrics.pageMargin
        spacing: Metrics.spacingL

        InlineStatusBanner {
            Layout.fillWidth: true
            message: NiriConfigService.busy || NiriConfigService.pendingMouseOptions !== null
                     ? qsTr("正在保存…") : qsTr("调整后自动保存并立即生效")
        }

        InlineStatusBanner {
            Layout.fillWidth: true
            visible: NiriConfigService.error !== "" || NiriConfigService.readError !== ""
            tone: "error"
            message: NiriConfigService.error || NiriConfigService.readError
        }

        SettingsSection {
            Layout.fillWidth: true
            title: qsTr("鼠标移动")
            iconName: "mouse"

            NiriSetupPrompt {
                Layout.fillWidth: true
                title: qsTr("启用鼠标设置")
                description: qsTr("启用后可在这里调整鼠标移动速度。")
                integrationState: NiriConfigService.state("mouse")
                busy: NiriConfigService.busy
                blocked: NiriConfigService.busy
                onSetupRequested: NiriConfigService.setup("mouse")
            }

            GeneralSliderSetting {
                objectName: "mouseSpeedSetting"
                enabled: NiriConfigService.ready("mouse")
                title: qsTr("移动速度")
                description: qsTr("向左更慢，向右更快；0 为默认速度。仅影响鼠标。")
                from: -100
                to: 100
                stepSize: 5
                value: Math.round(NiriConfigService.mouseOptions.speed * 100)
                onMoved: value => NiriConfigService.setMouseOptions({speed: value / 100})
            }

            SettingsRow {
                Layout.fillWidth: true
                title: qsTr("加速模式")
                supportingText: qsTr("自适应随移动速度加速；恒速保持固定比例。")
                trailing: SearchSelectMenuField {
                    objectName: "mouseAccelerationField"
                    implicitWidth: 180
                    implicitHeight: 40
                    enabled: NiriConfigService.ready("mouse")
                    options: [{label: qsTr("自适应"), value: "adaptive"},
                              {label: qsTr("恒速"), value: "flat"}]
                    value: NiriConfigService.mouseOptions.profile
                    onAccepted: value => NiriConfigService.setMouseOptions({profile: value})
                }
            }

            ActionButton {
                text: qsTr("恢复默认速度")
                iconName: "restart_alt"
                enabled: NiriConfigService.ready("mouse")
                onClicked: NiriConfigService.setMouseOptions({speed: 0, profile: "adaptive"})
            }
        }

        SettingsSection {
            Layout.fillWidth: true
            title: qsTr("光标外观")
            iconName: "arrow_selector_tool"

            NiriSetupPrompt {
                Layout.fillWidth: true
                title: qsTr("启用光标设置")
                description: qsTr("启用后可选择光标样式和大小。")
                integrationState: NiriConfigService.state("cursor")
                busy: NiriConfigService.busy
                blocked: NiriConfigService.busy
                onSetupRequested: NiriConfigService.setup("cursor")
            }

            SettingsRow {
                Layout.fillWidth: true
                title: qsTr("光标样式")
                supportingText: qsTr("选择已安装的光标主题")
                trailing: SearchSelectMenuField {
                    objectName: "mouseCursorThemeField"
                    implicitWidth: 240
                    implicitHeight: 40
                    enabled: NiriConfigService.ready("cursor")
                    options: ThemeService.availableCursorThemes
                    value: PersonalizationConfig.cursorTheme
                    placeholder: qsTr("选择光标主题")
                    onAccepted: value => ThemeService.setCursorTheme(value)
                }
            }

            GeneralSliderSetting {
                objectName: "mouseCursorSizeSetting"
                enabled: NiriConfigService.ready("cursor")
                title: qsTr("光标大小")
                description: qsTr("常用大小为 24、32 或 48 像素。")
                from: 12
                to: 128
                stepSize: 1
                suffix: qsTr(" 像素")
                value: PersonalizationConfig.cursorSize
                onMoved: value => ThemeService.setCursorSize(value)
            }
        }
    }
}
