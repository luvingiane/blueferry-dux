// What an empty tab shows: an icon, a line and an explanation.
import QtQuick
import qs.Common
import qs.DCommon.Widgets

Column {
    id: placeholder

    property string iconName
    property string text
    property string explanation

    spacing: Theme.spacingS

    DIcon {
        anchors.horizontalCenter: parent.horizontalCenter
        name: placeholder.iconName
        size: Theme.iconSizeLarge * 1.5
        color: Theme.surfaceVariantText
    }
    StyledText {
        width: parent.width
        text: placeholder.text
        horizontalAlignment: Text.AlignHCenter
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Theme.fontWeightMedium
        color: Theme.surfaceText
        wrapMode: Text.Wrap
    }
    StyledText {
        width: parent.width
        visible: text !== ""
        text: placeholder.explanation
        horizontalAlignment: Text.AlignHCenter
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.Wrap
    }
}
