// The Calls tab: the iPhone's recent calls (PBAP phone book through BlueFerry),
// with the contact's photo when BlueFerry keeps one.
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.DCommon.Widgets
import "util.js" as Util

Item {
    id: page

    required property var controller
    property var closePopout: null

    function directionIcon(direction) {
        switch (direction) {
        case "incoming": return "call_received"
        case "outgoing": return "call_made"
        case "missed": return "call_missed"
        default: return "call"
        }
    }

    function directionText(direction) {
        switch (direction) {
        case "incoming": return I18n.trFor("iphoneStatus", "Incoming")
        case "outgoing": return I18n.trFor("iphoneStatus", "Outgoing")
        case "missed": return I18n.trFor("iphoneStatus", "Missed")
        default: return ""
        }
    }

    DListView {
        anchors.fill: parent
        visible: page.controller.calls.length > 0
        clip: true
        spacing: Theme.spacingXS
        model: page.controller.calls

        delegate: Rectangle {
            id: entry
            required property var modelData
            readonly property string name: page.controller.callName(modelData)
            readonly property bool missed: modelData.direction === "missed"

            width: ListView.view.width
            implicitHeight: content.implicitHeight + Theme.spacingS * 2
            radius: Theme.cornerRadius
            color: Theme.cardSurface

            RowLayout {
                id: content
                anchors.fill: parent
                anchors.leftMargin: Theme.spacingM
                anchors.rightMargin: Theme.spacingS
                anchors.topMargin: Theme.spacingS
                anchors.bottomMargin: Theme.spacingS
                spacing: Theme.spacingM

                // The contact's photo, or their initials.
                Avatar {
                    source: page.controller.photos[entry.modelData.address] || ""
                    name: entry.name
                    Layout.preferredWidth: Theme.iconSizeLarge + Theme.spacingS
                    Layout.preferredHeight: Theme.iconSizeLarge + Theme.spacingS
                }

                ColumnLayout {
                    spacing: 0
                    Layout.fillWidth: true

                    StyledText {
                        text: page.controller.styled(entry.name)
                        textFormat: Text.StyledText
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: entry.missed ? Theme.fontWeightBold : Theme.fontWeightMedium
                        color: entry.missed ? Theme.error : Theme.surfaceText
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    RowLayout {
                        spacing: Theme.spacingXS
                        DIcon {
                            name: page.directionIcon(entry.modelData.direction)
                            size: Theme.iconSizeSmall
                            color: entry.missed ? Theme.error : Theme.surfaceVariantText
                        }
                        StyledText {
                            text: [page.directionText(entry.modelData.direction),
                                page.controller.timeText(new Date(entry.modelData.timestamp))]
                                .filter(part => part !== "").join(" · ")
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }
                }

                DActionButton {
                    visible: page.controller.callsEnabled && Util.isPhoneAddress(entry.modelData.address)
                    iconName: "call"
                    iconSize: Theme.iconSize
                    buttonSize: Theme.iconSize + Theme.spacingS * 2
                    iconColor: Theme.primary
                    tooltipText: I18n.trFor("iphoneStatus", "Call %1 back").arg(entry.name)
                    onClicked: page.controller.dial(entry.modelData.address)
                }
            }
        }
    }

    Placeholder {
        anchors.centerIn: parent
        width: parent.width - Theme.spacingL * 4
        visible: page.controller.calls.length === 0
        iconName: "call"
        text: I18n.trFor("iphoneStatus", "No recent calls")
        explanation: I18n.trFor("iphoneStatus", "BlueFerry's call history is empty or turned off (“blueferry call-history enable”).")
    }
}
