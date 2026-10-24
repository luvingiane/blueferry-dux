// The Notifications tab, in the style of the iPhone's notification centre: app
// icon on the left, bold title with the time, text below. SMS come from
// BlueFerry's history, everything else from the shell's notification server.
import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import qs.Common
import qs.DCommon.Widgets

Item {
    id: page

    required property var controller
    property var closePopout: null

    readonly property bool clickable: controller.notificationClick !== "none"

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.spacingXS
        visible: page.controller.notifications.length > 0

        RowLayout {
            spacing: Theme.spacingS
            Layout.fillWidth: true

            StyledText {
                readonly property int count: page.controller.notifications.length
                text: count === 1 ? I18n.trFor("iphoneStatus", "1 notification")
                    : I18n.trFor("iphoneStatus", "%1 notifications").arg(count)
                font.pixelSize: Theme.fontSizeMedium
                color: Theme.surfaceVariantText
                Layout.fillWidth: true
            }
            DActionButton {
                visible: page.controller.appNotifications.length > 0
                iconName: "clear_all"
                iconSize: Theme.iconSize
                buttonSize: Theme.iconSize + Theme.spacingS * 2
                tooltipText: I18n.trFor("iphoneStatus", "Clear the app notifications (SMS stay in BlueFerry)")
                onClicked: page.controller.clearNotifications()
            }
        }

        DListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: Theme.spacingXS
            model: page.controller.notifications

            delegate: Rectangle {
                id: entry
                required property var modelData
                required property int index
                readonly property string heading: modelData.title !== "" ? modelData.title : modelData.app
                readonly property string appIcon: page.controller.appIcon(modelData.app)
                readonly property bool opens: modelData.kind === "app" && page.clickable

                width: ListView.view.width
                implicitHeight: content.implicitHeight + Theme.spacingM * 2
                radius: Theme.cornerRadius
                color: rowMouse.containsMouse && entry.opens
                    ? Theme.withAlpha(Theme.primary, Theme.stateLayerHover) : Theme.cardSurface

                // A click opens the app (see the settings).
                MouseArea {
                    id: rowMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: entry.opens ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: {
                        if (page.controller.openNotification(entry.modelData) && page.closePopout)
                            page.closePopout()
                    }
                }

                RowLayout {
                    id: content
                    anchors.fill: parent
                    anchors.margins: Theme.spacingM
                    spacing: Theme.spacingM

                    // App icon; without a match in the theme, the bell with
                    // the phone in the bottom right corner.
                    Item {
                        Layout.preferredWidth: Theme.iconSizeLarge
                        Layout.preferredHeight: Theme.iconSizeLarge
                        Layout.alignment: Qt.AlignTop

                        IconImage {
                            anchors.fill: parent
                            visible: entry.appIcon !== ""
                            source: entry.appIcon
                            asynchronous: true
                        }
                        DIcon {
                            anchors.centerIn: parent
                            visible: entry.appIcon === ""
                            name: entry.modelData.kind === "sms" ? "sms" : "notifications"
                            size: Theme.iconSizeLarge
                            color: Theme.surfaceVariantText
                        }
                        DIcon {
                            visible: entry.appIcon === "" && entry.modelData.kind !== "sms"
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.rightMargin: -Theme.spacingXS
                            anchors.bottomMargin: -Theme.spacingXS
                            name: "smartphone"
                            size: Theme.iconSizeSmall
                            filled: true
                            color: Theme.primary
                        }
                    }

                    ColumnLayout {
                        spacing: Theme.spacingXS / 2
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignTop

                        RowLayout {
                            spacing: Theme.spacingS
                            Layout.fillWidth: true
                            StyledText {
                                text: page.controller.styled(entry.heading)
                                textFormat: Text.StyledText
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Theme.fontWeightBold
                                color: Theme.surfaceText
                                elide: Text.ElideRight
                                maximumLineCount: 1
                                Layout.fillWidth: true
                            }
                            StyledText {
                                text: page.controller.timeText(entry.modelData.time)
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                            }
                            DActionButton {
                                visible: entry.modelData.kind === "app"
                                opacity: rowMouse.containsMouse || hovered ? 1 : 0.5
                                iconName: "close"
                                iconSize: Theme.iconSizeSmall
                                buttonSize: Theme.iconSizeSmall + Theme.spacingS
                                tooltipText: I18n.trFor("iphoneStatus", "Clear, also on the iPhone")
                                onClicked: page.controller.removeNotification(entry.modelData)
                            }
                        }
                        StyledText {
                            visible: entry.modelData.body !== ""
                            text: page.controller.styled(entry.modelData.body)
                            textFormat: Text.StyledText
                            font.pixelSize: Theme.fontSizeMedium
                            color: Theme.surfaceText
                            wrapMode: Text.Wrap
                            maximumLineCount: 4
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }
                }
            }
        }
    }

    Placeholder {
        anchors.centerIn: parent
        width: parent.width - Theme.spacingL * 4
        visible: page.controller.notifications.length === 0
        iconName: "notifications_off"
        text: I18n.trFor("iphoneStatus", "No notifications")
        explanation: I18n.trFor("iphoneStatus", "SMS come from BlueFerry's history. App notifications show up here from the moment the plugin is running, because the iPhone does not send them again.")
    }
}
