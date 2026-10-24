// The popup: the phone's name and link state, then the tabs (Status,
// Notifications, Player, Calls) in the order chosen in the settings.
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.DCommon.Widgets

Item {
    id: popup

    property var controller: null
    property var closePopout: null

    readonly property bool ready: !!controller
    readonly property var tabs: ready && controller.popupTabs.length > 0 ? controller.popupTabs : ["status"]
    readonly property string version: String(Date.now())
    property int currentIndex: ready ? Math.max(0, tabs.indexOf(controller.lastTab)) : 0

    function tabLabel(id) {
        switch (id) {
        case "status": return I18n.trFor("iphoneStatus", "Status")
        case "notifications": return I18n.trFor("iphoneStatus", "Notifications")
        case "player": return I18n.trFor("iphoneStatus", "Player")
        case "calls": return I18n.trFor("iphoneStatus", "Calls")
        default: return id
        }
    }

    function tabIcon(id) {
        switch (id) {
        case "status": return "phone_iphone"
        case "notifications": return "notifications"
        case "player": return "music_note"
        case "calls": return "call"
        default: return ""
        }
    }

    function pageFile(id) {
        switch (id) {
        case "notifications": return "NotificationsPage.qml"
        case "player": return "PlayerPage.qml"
        case "calls": return "CallsPage.qml"
        default: return "StatusPage.qml"
        }
    }

    implicitWidth: 400
    implicitHeight: 540

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.spacingS

        RowLayout {
            spacing: Theme.spacingM
            Layout.fillWidth: true

            DIcon {
                name: "phone_iphone"
                size: Theme.iconSizeLarge
                filled: true
                color: popup.ready && popup.controller.active ? Theme.primary : Theme.surfaceVariantText
            }
            ColumnLayout {
                spacing: 0
                Layout.fillWidth: true

                StyledText {
                    text: popup.ready ? popup.controller.styled(popup.controller.title) : ""
                    textFormat: Text.StyledText
                    font.pixelSize: Theme.fontSizeLarge
                    font.weight: Theme.fontWeightBold
                    color: Theme.surfaceText
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                StyledText {
                    readonly property bool on: popup.ready && popup.controller.active
                    text: on ? I18n.trFor("iphoneStatus", "Connected") : I18n.trFor("iphoneStatus", "Disconnected")
                    font.pixelSize: Theme.fontSizeSmall
                    color: on ? Theme.success : Theme.surfaceVariantText
                    Layout.fillWidth: true
                }
            }
            DActionButton {
                iconName: "refresh"
                iconSize: Theme.iconSize
                buttonSize: Theme.iconSize + Theme.spacingM * 2
                tooltipText: I18n.trFor("iphoneStatus", "Refresh")
                onClicked: popup.controller?.refreshAll()
            }
        }

        DTabBar {
            id: tabBar
            visible: popup.tabs.length > 1
            Layout.fillWidth: true
            currentIndex: popup.currentIndex
            model: popup.tabs.map(id => ({ text: popup.tabLabel(id), icon: popup.tabIcon(id) }))
            onTabClicked: index => {
                popup.currentIndex = index
                if (popup.controller)
                    popup.controller.lastTab = popup.tabs[index]
            }
        }

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: Math.min(popup.currentIndex, popup.tabs.length - 1)

            Repeater {
                model: popup.tabs

                delegate: Loader {
                    id: page
                    required property string modelData
                    required property int index
                    readonly property bool current: index === popup.currentIndex
                    property bool started: false

                    // A page loads when it is first shown and receives the
                    // daemon as an initial property, so its bindings never
                    // see a null controller.
                    function start() {
                        if (!current || started || !popup.ready)
                            return
                        started = true
                        setSource(Qt.resolvedUrl(popup.pageFile(modelData)).toString() + "?v=" + popup.version, {
                            controller: popup.controller,
                            closePopout: popup.closePopout
                        })
                    }

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    onCurrentChanged: start()
                    Component.onCompleted: start()
                    Connections {
                        target: popup
                        function onReadyChanged() {
                            page.start()
                        }
                    }
                }
            }
        }
    }
}
