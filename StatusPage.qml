// The Status tab: battery, cellular network and Bluetooth as sections (icon,
// title and value, bar, detail), in the order chosen in the settings.
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.DCommon.Widgets

Item {
    id: page

    required property var controller
    property var closePopout: null

    function batterySourceText(source) {
        switch (source) {
        case "gatt": return I18n.trFor("iphoneStatus", "Bluetooth LE, exact value")
        case "bluez": return I18n.trFor("iphoneStatus", "Bluetooth LE, through BlueZ")
        case "hfp": return I18n.trFor("iphoneStatus", "Hands-free, in 20 % steps")
        default: return ""
        }
    }

    // {icon, title, value, progress (0-100, or -1 without a bar), detail}
    function section(id) {
        const c = controller
        switch (id) {
        case "battery":
            return {
                icon: c.batteryIcon,
                title: I18n.trFor("iphoneStatus", "Battery"),
                value: c.batteryText,
                progress: c.active && c.batteryLevel !== null ? c.batteryLevel : -1,
                detail: !c.active ? ""
                    : c.charging ? batterySourceText(c.batterySource) + " · " + c.chargingText
                    : batterySourceText(c.batterySource)
            }
        case "network": {
            const parts = []
            if (c.networkText !== c.dash)
                parts.push(c.networkText)
            if (c.wifiCalling)
                parts.push(I18n.trFor("iphoneStatus", "Wi-Fi calling"))
            const registration = c.registrationText(c.networkStatus)
            if (registration !== c.dash)
                parts.push(registration)
            return {
                icon: c.wifiCalling && c.active ? "wifi_calling_3" : c.signalIcon,
                title: I18n.trFor("iphoneStatus", "Cellular network"),
                value: c.signalBars < 0 ? c.dash : I18n.trFor("iphoneStatus", "%1/5").arg(c.signalBars),
                progress: c.active && c.signalStrength !== null ? c.signalStrength : -1,
                detail: c.active ? parts.join(" · ") : ""
            }
        }
        case "bluetooth":
            return {
                icon: c.active ? "bluetooth_connected" : "bluetooth_disabled",
                title: I18n.trFor("iphoneStatus", "Bluetooth"),
                value: !c.loaded || c.error !== "" ? c.dash
                    : c.connected ? I18n.trFor("iphoneStatus", "Connected") : I18n.trFor("iphoneStatus", "Disconnected"),
                progress: -1,
                detail: c.connectivityDetail
            }
        default:
            return { icon: "help", title: id, value: "", progress: -1, detail: "" }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: Theme.spacingS
        spacing: Theme.spacingM

        // Why the phone cannot be read.
        Rectangle {
            visible: page.controller.loaded && page.controller.reason !== ""
            Layout.fillWidth: true
            implicitHeight: warning.implicitHeight + Theme.spacingM * 2
            radius: Theme.cornerRadius
            color: Theme.withAlpha(Theme.warning, 0.15)

            RowLayout {
                id: warning
                anchors.fill: parent
                anchors.margins: Theme.spacingM
                spacing: Theme.spacingS

                DIcon {
                    name: "warning"
                    size: Theme.iconSize
                    color: Theme.warning
                    Layout.alignment: Qt.AlignTop
                }
                StyledText {
                    text: page.controller.reason
                    color: Theme.surfaceText
                    font.pixelSize: Theme.fontSizeMedium
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                }
            }
        }

        Repeater {
            model: page.controller.statusSections

            delegate: Rectangle {
                id: row
                required property string modelData
                readonly property var info: page.section(modelData)

                Layout.fillWidth: true
                implicitHeight: content.implicitHeight + Theme.spacingM * 2
                radius: Theme.cornerRadius
                color: Theme.cardSurface

                RowLayout {
                    id: content
                    anchors.fill: parent
                    anchors.margins: Theme.spacingM
                    spacing: Theme.spacingM

                    DIcon {
                        name: row.info.icon
                        size: Theme.iconSizeLarge
                        color: page.controller.active ? Theme.primary : Theme.surfaceVariantText
                        Layout.alignment: Qt.AlignTop
                    }

                    ColumnLayout {
                        spacing: Theme.spacingXS
                        Layout.fillWidth: true

                        RowLayout {
                            spacing: Theme.spacingS
                            Layout.fillWidth: true
                            StyledText {
                                text: row.info.title
                                font.pixelSize: Theme.fontSizeMedium
                                color: Theme.surfaceText
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            StyledText {
                                text: row.info.value
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Theme.fontWeightBold
                                color: Theme.surfaceText
                            }
                        }

                        Meter {
                            visible: row.info.progress >= 0
                            value: Math.max(0, row.info.progress)
                            Layout.fillWidth: true
                        }

                        StyledText {
                            visible: row.info.detail !== ""
                            text: page.controller.styled(row.info.detail)
                            textFormat: Text.StyledText
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            wrapMode: Text.Wrap
                            Layout.fillWidth: true
                        }
                    }
                }
            }
        }

        Item { Layout.fillHeight: true }

        StyledText {
            visible: page.controller.loaded
            text: I18n.trFor("iphoneStatus", "Updated at %1").arg(Qt.formatTime(page.controller.lastUpdate, "hh:mm:ss"))
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            horizontalAlignment: Text.AlignRight
            Layout.fillWidth: true
        }
    }
}
