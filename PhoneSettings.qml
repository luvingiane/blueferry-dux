// The settings: the title, which items to show and in what order in the bar
// and the popup, notification clicks, artwork and the emoji font.
import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Plugins
import "order.js" as Order

PluginSettings {
    id: root
    pluginId: "iphoneStatus"

    StringSetting {
        settingKey: "title"
        label: I18n.trFor("iphoneStatus", "Title")
        description: I18n.trFor("iphoneStatus", "Shown in the popup, the tooltip and the bar.")
        placeholder: I18n.trFor("iphoneStatus", "iPhone")
        defaultValue: ""
    }

    OrderSetting {
        settings: root
        settingKey: "panelItems"
        label: I18n.trFor("iphoneStatus", "Bar items")
        description: I18n.trFor("iphoneStatus", "Vertical bars show only the icons, the battery level and the notification count.")
        ids: Order.PANEL_IDS
        defaultValue: Order.PANEL_DEFAULT
        labels: ({
            batteryIcon: I18n.trFor("iphoneStatus", "Battery icon"),
            batteryText: I18n.trFor("iphoneStatus", "Battery percentage"),
            signalIcon: I18n.trFor("iphoneStatus", "Signal icon"),
            signalText: I18n.trFor("iphoneStatus", "Signal percentage"),
            operator: I18n.trFor("iphoneStatus", "Carrier"),
            title: I18n.trFor("iphoneStatus", "Title"),
            media: I18n.trFor("iphoneStatus", "Now playing"),
            notifications: I18n.trFor("iphoneStatus", "New notification count")
        })
    }

    OrderSetting {
        settings: root
        settingKey: "popupTabs"
        label: I18n.trFor("iphoneStatus", "Popup tabs")
        ids: Order.TAB_IDS
        defaultValue: Order.TAB_DEFAULT
        labels: ({
            status: I18n.trFor("iphoneStatus", "Status"),
            notifications: I18n.trFor("iphoneStatus", "Notifications"),
            player: I18n.trFor("iphoneStatus", "Player"),
            calls: I18n.trFor("iphoneStatus", "Recent calls")
        })
    }

    OrderSetting {
        settings: root
        settingKey: "statusSections"
        label: I18n.trFor("iphoneStatus", "Status sections")
        ids: Order.SECTION_IDS
        defaultValue: Order.SECTION_DEFAULT
        labels: ({
            battery: I18n.trFor("iphoneStatus", "Battery"),
            network: I18n.trFor("iphoneStatus", "Cellular network"),
            bluetooth: I18n.trFor("iphoneStatus", "Bluetooth")
        })
    }

    SelectionSetting {
        settingKey: "notificationClick"
        label: I18n.trFor("iphoneStatus", "Clicking a notification")
        options: [
            { label: I18n.trFor("iphoneStatus", "Opens the app, or else its web version"), value: "app" },
            { label: I18n.trFor("iphoneStatus", "Opens the app only"), value: "appOnly" },
            { label: I18n.trFor("iphoneStatus", "Does nothing"), value: "none" }
        ]
        defaultValue: "app"
    }

    ToggleSetting {
        settingKey: "onlineArtwork"
        label: I18n.trFor("iphoneStatus", "Look the artwork up online on iTunes")
        description: I18n.trFor("iphoneStatus", "The iPhone does not send artwork over Bluetooth. During AirPlay it comes from shairport-sync; otherwise the artist and title are looked up with the iTunes API.")
        defaultValue: true
    }

    SelectionSetting {
        settingKey: "airplayDuplicate"
        label: I18n.trFor("iphoneStatus", "AirPlay from the iPhone in the shell's player")
        description: I18n.trFor("iphoneStatus", "While shairport-sync plays the same track as BlueFerry's player, the shell lists it twice. BlueFerry's has the working controls, shairport-sync's has the artwork.")
        options: [
            { label: I18n.trFor("iphoneStatus", "Show only BlueFerry's player (no artwork there)"), value: "hide" },
            { label: I18n.trFor("iphoneStatus", "Prefer BlueFerry's player, keep the artwork"), value: "prefer" },
            { label: I18n.trFor("iphoneStatus", "Leave both"), value: "off" }
        ]
        defaultValue: "hide"
    }

    StringSetting {
        settingKey: "emojiFont"
        label: I18n.trFor("iphoneStatus", "Emoji font")
        description: I18n.trFor("iphoneStatus", "For emoji in notifications, names and tracks; empty: the theme font.")
        placeholder: "Apple Color Emoji"
        defaultValue: "Apple Color Emoji"
    }

    StyledText {
        width: parent.width
        text: I18n.trFor("iphoneStatus", "The network type (LTE, 5G…) is not available: the iPhone's Bluetooth hands-free profile does not report it.")
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }
}
