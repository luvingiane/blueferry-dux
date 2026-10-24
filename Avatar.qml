// A contact's round photo, or their initials on a colour derived from the name.
import QtQuick
import Quickshell.Widgets
import qs.Common
import qs.DCommon.Widgets
import "util.js" as Util

Item {
    id: avatar

    property string source
    property string name

    readonly property string initials: Util.initials(name)

    // A stable tint per name, as address books do.
    readonly property color tint: {
        let hash = 0
        for (let i = 0; i < name.length; ++i)
            hash = (hash * 31 + name.charCodeAt(i)) >>> 0
        return Qt.hsla((hash % 360) / 360, 0.45, 0.45, 1)
    }

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: avatar.tint
        visible: photo.status !== Image.Ready

        StyledText {
            anchors.centerIn: parent
            visible: avatar.initials !== ""
            text: avatar.initials
            color: "white"
            font.weight: Theme.fontWeightBold
            font.pixelSize: parent.height * 0.4
        }
        DIcon {
            anchors.centerIn: parent
            visible: avatar.initials === ""
            name: "person"
            size: parent.height * 0.6
            color: "white"
        }
    }

    ClippingRectangle {
        anchors.fill: parent
        radius: width / 2
        color: "transparent"
        visible: photo.status === Image.Ready

        Image {
            id: photo
            anchors.fill: parent
            source: avatar.source
            sourceSize.width: avatar.width * 2
            sourceSize.height: avatar.height * 2
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
        }
    }
}
