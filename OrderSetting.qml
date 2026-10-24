// A setting with items to show or hide and reorder with the arrows, saved as
// an array of ids ("-id" for a hidden one, see order.js).
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.DCommon.Widgets
import "order.js" as Order

Column {
    id: setting

    required property var settings      // the PluginSettings that stores it
    required property string settingKey
    required property string label
    property string description: ""
    property var ids: []
    property var labels: ({})
    property var defaultValue: []

    property var entries: defaultValue
    readonly property var items: Order.parse(entries, ids)

    function loadValue() {
        entries = settings.loadValue(settingKey, defaultValue)
    }

    function save(next) {
        entries = Order.serialize(next)
        settings.saveValue(settingKey, entries)
    }

    function copy() {
        return items.map(item => ({ id: item.id, shown: item.shown }))
    }

    function move(from, to) {
        const next = copy()
        const moved = next.splice(from, 1)[0]
        next.splice(to, 0, moved)
        save(next)
    }

    function toggle(index, shown) {
        const next = copy()
        next[index].shown = shown
        save(next)
    }

    width: parent ? parent.width : 0
    spacing: Theme.spacingXS

    Component.onCompleted: Qt.callLater(loadValue)

    StyledText {
        width: parent.width
        text: setting.label
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Theme.fontWeightMedium
        color: Theme.surfaceText
    }
    StyledText {
        width: parent.width
        visible: text !== ""
        text: setting.description
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    Repeater {
        model: setting.items

        delegate: Rectangle {
            required property var modelData
            required property int index

            width: setting.width
            height: row.implicitHeight + Theme.spacingXS * 2
            radius: Theme.cornerRadius
            color: Theme.chipSurface

            RowLayout {
                id: row
                anchors.fill: parent
                anchors.leftMargin: Theme.spacingM
                anchors.rightMargin: Theme.spacingXS
                spacing: Theme.spacingXS

                StyledText {
                    text: setting.labels[modelData.id] || modelData.id
                    font.pixelSize: Theme.fontSizeMedium
                    color: modelData.shown ? Theme.surfaceText : Theme.surfaceVariantText
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                DActionButton {
                    iconName: "arrow_upward"
                    iconSize: Theme.iconSizeSmall
                    buttonSize: Theme.iconSizeSmall + Theme.spacingS * 2
                    enabled: index > 0
                    opacity: enabled ? 1 : 0.3
                    tooltipText: I18n.trFor("iphoneStatus", "Move up")
                    onClicked: setting.move(index, index - 1)
                }
                DActionButton {
                    iconName: "arrow_downward"
                    iconSize: Theme.iconSizeSmall
                    buttonSize: Theme.iconSizeSmall + Theme.spacingS * 2
                    enabled: index < setting.items.length - 1
                    opacity: enabled ? 1 : 0.3
                    tooltipText: I18n.trFor("iphoneStatus", "Move down")
                    onClicked: setting.move(index, index + 1)
                }
                DToggle {
                    checked: modelData.shown
                    onToggled: isChecked => setting.toggle(index, isChecked)
                }
            }
        }
    }
}
