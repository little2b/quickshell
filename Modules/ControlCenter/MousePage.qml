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
    onPresentationActiveChanged: if (presentationActive)
                                     NiriConfigService.refresh()

    ColumnLayout {
        id: contentColumn
        width: Math.min(640, Math.max(0, root.width - Metrics.pageMargin * 2))
        x: Math.max(Metrics.pageMargin, (root.width - width) / 2)
        y: Metrics.pageMargin
        spacing: Metrics.spacingL

        InlineStatusBanner {
            Layout.fillWidth: true
            message: NiriConfigService.busy || NiriConfigService.pendingMouseOptions !== null ? qsTr(
                                                                                                    "Saving…") :
                                                                                                qsTr("Changes are saved and applied automatically")
        }

        InlineStatusBanner {
            Layout.fillWidth: true
            visible: NiriConfigService.error !== "" || NiriConfigService.readError !== ""
            tone: "error"
            message: NiriConfigService.error || NiriConfigService.readError
        }

        SettingsSection {
            Layout.fillWidth: true
            title: qsTr("Pointer motion")
            iconName: "mouse"

            NiriSetupPrompt {
                Layout.fillWidth: true
                title: qsTr("Enable mouse settings")
                description: qsTr("Enable this to adjust mouse pointer speed here.")
                integrationState: NiriConfigService.state("mouse")
                busy: NiriConfigService.busy
                blocked: NiriConfigService.busy
                onSetupRequested: NiriConfigService.setup("mouse")
            }

            GeneralSliderSetting {
                objectName: "mouseSpeedSetting"
                enabled: NiriConfigService.ready("mouse")
                title: qsTr("Pointer speed")
                description: qsTr(
                                 "Move left for slower motion or right for faster motion. The default is 0. Only affects the mouse.")
                from: -100
                to: 100
                stepSize: 5
                value: Math.round(NiriConfigService.mouseOptions.speed * 100)
                onMoved: value => NiriConfigService.setMouseOptions({
                                                                        speed: value / 100
                                                                    })
            }

            SettingsRow {
                Layout.fillWidth: true
                title: qsTr("Acceleration profile")
                supportingText: qsTr(
                                    "Adaptive acceleration depends on movement speed. Flat acceleration uses a fixed ratio.")
                trailing: SearchSelectMenuField {
                    objectName: "mouseAccelerationField"
                    implicitWidth: 180
                    implicitHeight: 40
                    enabled: NiriConfigService.ready("mouse")
                    options: [
                        {
                            label: qsTr("Adaptive"),
                            value: "adaptive"
                        },
                        {
                            label: qsTr("Flat"),
                            value: "flat"
                        }
                    ]
                    value: NiriConfigService.mouseOptions.profile
                    onAccepted: value => NiriConfigService.setMouseOptions({
                                                                               profile: value
                                                                           })
                }
            }

            ActionButton {
                text: qsTr("Reset pointer speed")
                iconName: "restart_alt"
                enabled: NiriConfigService.ready("mouse")
                onClicked: NiriConfigService.setMouseOptions({
                                                                 speed: 0,
                                                                 profile: "adaptive"
                                                             })
            }
        }

        SettingsSection {
            Layout.fillWidth: true
            title: qsTr("Cursor appearance")
            iconName: "arrow_selector_tool"

            NiriSetupPrompt {
                Layout.fillWidth: true
                title: qsTr("Enable cursor settings")
                description: qsTr("Enable this to select a cursor theme and size.")
                integrationState: NiriConfigService.state("cursor")
                busy: NiriConfigService.busy
                blocked: NiriConfigService.busy
                onSetupRequested: NiriConfigService.setup("cursor")
            }

            SettingsRow {
                Layout.fillWidth: true
                title: qsTr("Cursor theme")
                supportingText: qsTr("Choose an installed cursor theme")
                trailing: SearchSelectMenuField {
                    objectName: "mouseCursorThemeField"
                    implicitWidth: 240
                    implicitHeight: 40
                    enabled: NiriConfigService.ready("cursor")
                    options: ThemeService.availableCursorThemes
                    value: PersonalizationConfig.cursorTheme
                    placeholder: qsTr("Choose cursor theme")
                    onAccepted: value => ThemeService.setCursorTheme(value)
                }
            }

            GeneralSliderSetting {
                objectName: "mouseCursorSizeSetting"
                enabled: NiriConfigService.ready("cursor")
                title: qsTr("Cursor size")
                description: qsTr("Common sizes are 24, 32 or 48 pixels.")
                from: 12
                to: 128
                stepSize: 1
                suffix: qsTr(" px")
                value: PersonalizationConfig.cursorSize
                onMoved: value => ThemeService.setCursorSize(value)
            }
        }
    }
}
