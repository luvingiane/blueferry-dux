// The bar widget: the iPhone's battery, signal, carrier, track and new
// notifications, in the order chosen in the settings, and the tabbed popup.
// The data comes from the daemon (PhoneDaemon.qml), shared as "controller".
import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Plugins
import qs.Widgets as ShellWidgets

PluginComponent {
    id: root

    ShellWidgets.PluginGlobalVar {
        id: shared
        varName: "controller"
        defaultValue: null
    }

    readonly property var controller: shared.value
    readonly property bool ready: !!controller
    readonly property var items: ready ? controller.panelVisible : ["placeholder"]

    function itemIcon(id) {
        return ready ? controller.panelIcon(id) : "phone_iphone"
    }

    function itemText(id) {
        if (!ready || id === "batteryIcon" || id === "signalIcon" || id === "placeholder")
            return ""
        return controller.panelText(id)
    }

    // The player and the notifications still make sense with the phone
    // unreachable; the rest is dimmed.
    function dimmed(id) {
        return !ready || !controller.active && id !== "media" && id !== "notifications"
    }

    // The popup tells the daemon it is open: the player is read more often
    // and new notifications are not counted as unseen.
    readonly property string popupOwner: "widget-" + (widgetInstanceId || Math.random())
    onInteractionActiveChanged: {
        if (controller)
            controller.setPopupOpen(popupOwner, interactionActive)
        if (interactionActive)
            tooltip.hide()
    }
    Component.onDestruction: {
        if (controller)
            controller.setPopupOpen(popupOwner, false)
    }

    popoutWidth: 440
    popoutContent: Component {
        Item {
            id: content

            property var closePopout: null
            property var parentPopout: null

            implicitHeight: 540

            // The shell reloads the widget's own file on a plugin reload, not
            // the files it imports: the popup is loaded with a fresh URL so
            // that a reload updates it too.
            Loader {
                anchors.fill: parent
                Component.onCompleted: setSource(Qt.resolvedUrl("PhonePopout.qml").toString() + "?v=" + Date.now(), {
                    controller: Qt.binding(() => root.controller),
                    closePopout: Qt.binding(() => content.closePopout)
                })
            }
        }
    }

    // Control Center tile: battery and carrier, the Status tab as detail.
    ccWidgetIcon: ready ? controller.batteryIcon : "phone_iphone"
    ccWidgetPrimaryText: ready ? controller.title : I18n.trFor("iphoneStatus", "iPhone")
    ccWidgetSecondaryText: !ready ? "" : controller.active
        ? [controller.batteryText, controller.networkText].filter(part => part !== controller.dash).join(" · ")
        : controller.reason
    ccWidgetIsActive: ready && controller.active
    ccWidgetIsToggle: false
    ccDetailHeight: 320
    ccDetailContent: Component {
        Item {
            implicitHeight: 320

            Loader {
                anchors.fill: parent
                anchors.margins: Theme.spacingM
                active: root.ready
                Component.onCompleted: setSource(Qt.resolvedUrl("StatusPage.qml").toString() + "?v=" + Date.now(), {
                    controller: Qt.binding(() => root.controller)
                })
            }
        }
    }

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS

            Repeater {
                model: root.items

                delegate: Row {
                    id: element
                    required property string modelData
                    readonly property string icon: root.itemIcon(modelData)
                    readonly property string text: root.itemText(modelData)

                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingXS / 2
                    opacity: root.dimmed(modelData) ? 0.5 : 1

                    DIcon {
                        visible: element.icon !== ""
                        anchors.verticalCenter: parent.verticalCenter
                        name: element.icon
                        size: element.modelData === "media" ? Math.round(root.iconSize * 0.75) : root.iconSize
                        color: Theme.widgetIconColor
                    }
                    StyledText {
                        visible: element.text !== ""
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.ready ? root.controller.styled(element.text) : ""
                        textFormat: Text.StyledText
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        width: element.modelData === "media" ? Math.min(implicitWidth, Theme.fontSizeMedium * 14) : implicitWidth
                        font.pixelSize: root.textSize
                        color: Theme.widgetTextColor
                    }
                    // Wi-Fi calling, in place of the cut "Wi F" after the
                    // operator.
                    DIcon {
                        visible: element.modelData === "operator" && root.ready && root.controller.wifiCalling
                            && element.text !== ""
                        anchors.verticalCenter: parent.verticalCenter
                        name: "wifi"
                        size: Math.round(root.iconSize * 0.75)
                        color: Theme.widgetIconColor
                    }
                }
            }
        }
    }

    // Vertical bars have room for icons and numbers only.
    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingXS

            Repeater {
                model: root.items.filter(id => id !== "operator" && id !== "title" && id !== "signalText")

                delegate: Item {
                    id: element
                    required property string modelData
                    readonly property string icon: modelData === "batteryText" ? "" : root.itemIcon(modelData)
                    readonly property string text: modelData === "batteryText"
                        ? (root.ready && root.controller.batteryLevel !== null ? String(root.controller.batteryLevel) : "")
                        : modelData === "notifications" ? root.itemText(modelData) : ""

                    anchors.horizontalCenter: parent.horizontalCenter
                    implicitWidth: Math.max(iconItem.visible ? iconItem.width : 0, label.visible ? label.implicitWidth : 0)
                    implicitHeight: (iconItem.visible ? iconItem.height : 0) + (label.visible ? label.implicitHeight : 0)
                    width: implicitWidth
                    height: implicitHeight
                    opacity: root.dimmed(modelData) ? 0.5 : 1

                    DIcon {
                        id: iconItem
                        visible: element.icon !== ""
                        anchors.horizontalCenter: parent.horizontalCenter
                        name: element.icon
                        size: root.iconSize
                        color: Theme.widgetIconColor
                    }
                    StyledText {
                        id: label
                        visible: element.text !== ""
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        text: element.text
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.widgetTextColor
                    }
                }
            }
        }
    }

    HoverHandler {
        id: hover
        onHoveredChanged: {
            if (hovered && !root.interactionActive)
                hoverDelay.restart()
            else {
                hoverDelay.stop()
                tooltip.hide()
            }
        }
    }

    Timer {
        id: hoverDelay
        interval: 600
        onTriggered: {
            if (!root.ready)
                return
            const below = !root.isVertical && (root.barConfig?.position ?? 0) === 0
            const pos = root.isVertical ? root.mapToItem(null, root.width + Theme.spacingS, 0)
                : root.mapToItem(null, root.width / 2, below ? root.height + Theme.spacingS : -Theme.spacingS * 12)
            tooltip.show(root.controller.tooltip, pos.x, pos.y, root.parentScreen)
        }
    }

    ShellWidgets.DTooltip {
        id: tooltip
    }
}
