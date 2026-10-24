// A thin progress bar in the theme's colours.
import QtQuick
import qs.Common

Rectangle {
    id: meter

    property real value: 0
    property real from: 0
    property real to: 100
    property color fillColor: Theme.primary

    readonly property real fraction: to > from ? Math.max(0, Math.min(1, (value - from) / (to - from))) : 0

    implicitHeight: 6
    radius: height / 2
    color: Theme.withAlpha(Theme.surfaceText, 0.12)

    Rectangle {
        width: parent.width * meter.fraction
        height: parent.height
        radius: parent.radius
        color: meter.fillColor
    }
}
