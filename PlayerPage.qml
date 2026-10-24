// The Player tab: blurred artwork background, artwork, title, progress and
// controls. The track comes from the iPhone (Apple Media Service through
// BlueFerry) or from AirPlay (shairport-sync); the artwork from shairport-sync
// or the iTunes search.
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell.Widgets
import qs.Common
import qs.DCommon.Widgets

Item {
    id: page

    required property var controller
    property var closePopout: null

    readonly property var track: controller.track
    readonly property real artSize: Math.max(96, Math.min(width - 120, height * 0.42))

    // A player button, enabled when BlueFerry offers the command (or does not
    // list any yet).
    component MediaButton: DActionButton {
        required property var controller
        property string command
        property int size: Theme.iconSize
        enabled: controller.canCommand(command)
        opacity: enabled ? 1 : 0.4
        iconSize: size
        buttonSize: size + Theme.spacingM * 2
        iconColor: Theme.surfaceText
        onClicked: controller.mediaCommand(command)
    }

    // Background: the artwork, blurred and dimmed.
    ClippingRectangle {
        anchors.fill: parent
        radius: Theme.cornerRadius
        color: "transparent"
        visible: page.controller.mediaAvailable && backgroundArt.status === Image.Ready

        Image {
            id: backgroundArt
            anchors.fill: parent
            source: page.controller.artwork
            sourceSize.width: 256
            sourceSize.height: 256
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            visible: false
        }
        MultiEffect {
            anchors.fill: parent
            source: backgroundArt
            blurEnabled: true
            blurMax: 64
            blur: 1.0
            saturation: 0.3
            opacity: 0.3
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacingM
        visible: page.controller.mediaAvailable
        spacing: Theme.spacingXS

        Item { Layout.fillHeight: true }

        Item {
            Layout.preferredWidth: page.artSize
            Layout.preferredHeight: page.artSize
            Layout.alignment: Qt.AlignHCenter
            Layout.bottomMargin: Theme.spacingM

            Rectangle {
                anchors.fill: parent
                radius: Theme.cornerRadiusL
                color: Theme.cardSurface
                visible: art.status !== Image.Ready
                DIcon {
                    anchors.centerIn: parent
                    name: "music_note"
                    size: parent.width * 0.45
                    color: Theme.surfaceVariantText
                }
            }
            ClippingRectangle {
                anchors.fill: parent
                radius: Theme.cornerRadiusL
                color: "transparent"
                visible: art.status === Image.Ready

                Image {
                    id: art
                    anchors.fill: parent
                    source: page.controller.artwork
                    sourceSize.width: page.artSize * 2
                    sourceSize.height: page.artSize * 2
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }
            }
        }

        StyledText {
            text: page.controller.styled(page.track ? page.track.title || I18n.trFor("iphoneStatus", "Untitled") : "")
            textFormat: Text.StyledText
            font.pixelSize: Theme.fontSizeXLarge
            font.weight: Theme.fontWeightBold
            color: Theme.surfaceText
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
            Layout.fillWidth: true
        }
        StyledText {
            visible: text !== ""
            text: page.controller.styled(page.track ? page.track.artist || "" : "")
            textFormat: Text.StyledText
            font.pixelSize: Theme.fontSizeMedium
            color: Theme.surfaceText
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
            Layout.fillWidth: true
        }
        StyledText {
            visible: text !== ""
            text: page.controller.styled(page.track ? page.track.album || "" : "")
            textFormat: Text.StyledText
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
            Layout.fillWidth: true
        }

        RowLayout {
            visible: page.controller.mediaHasProgress
            spacing: Theme.spacingS
            Layout.fillWidth: true
            Layout.topMargin: Theme.spacingM

            StyledText {
                text: page.controller.durationText(page.controller.mediaElapsed)
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
            }
            Meter {
                from: 0
                to: page.controller.mediaDuration
                value: page.controller.mediaElapsed
                Layout.fillWidth: true
            }
            StyledText {
                text: page.controller.durationText(page.controller.mediaDuration)
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
            }
        }

        RowLayout {
            spacing: Theme.spacingL
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Theme.spacingS

            MediaButton {
                controller: page.controller
                command: "previous"
                iconName: "skip_previous"
                tooltipText: I18n.trFor("iphoneStatus", "Previous")
            }
            MediaButton {
                controller: page.controller
                command: "toggle"
                size: Theme.iconSizeLarge
                iconName: page.controller.playing ? "pause" : "play_arrow"
                iconFilled: true
                iconColor: Theme.onPrimary
                backgroundColor: Theme.primary
                tooltipText: page.controller.playing ? I18n.trFor("iphoneStatus", "Pause") : I18n.trFor("iphoneStatus", "Play")
            }
            MediaButton {
                controller: page.controller
                command: "next"
                iconName: "skip_next"
                tooltipText: I18n.trFor("iphoneStatus", "Next")
            }
        }

        RowLayout {
            visible: page.controller.hasVolume
            spacing: Theme.spacingS
            Layout.alignment: Qt.AlignHCenter

            MediaButton {
                controller: page.controller
                command: "volume-down"
                size: Theme.iconSizeSmall
                iconName: "volume_down"
                tooltipText: I18n.trFor("iphoneStatus", "Volume down")
            }
            Meter {
                from: 0
                to: 1
                value: page.controller.hasVolume ? page.controller.player.volume : 0
                Layout.preferredWidth: 120
            }
            MediaButton {
                controller: page.controller
                command: "volume-up"
                size: Theme.iconSizeSmall
                iconName: "volume_up"
                tooltipText: I18n.trFor("iphoneStatus", "Volume up")
            }
        }

        StyledText {
            visible: page.controller.mediaError !== ""
            text: I18n.trFor("iphoneStatus", "BlueFerry refused the command: %1").arg(page.controller.mediaError)
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.error
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
            Layout.fillWidth: true
        }

        StyledText {
            text: page.controller.mediaSource
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            horizontalAlignment: Text.AlignHCenter
            Layout.fillWidth: true
        }

        Item { Layout.fillHeight: true }
    }

    Placeholder {
        anchors.centerIn: parent
        width: parent.width - Theme.spacingL * 4
        visible: !page.controller.mediaAvailable
        iconName: "music_off"
        text: I18n.trFor("iphoneStatus", "Nothing playing")
        explanation: {
            const status = page.controller.nowPlaying
            if (!status)
                return I18n.trFor("iphoneStatus", "BlueFerry did not answer about the player.")
            if (status.enabled === false)
                return I18n.trFor("iphoneStatus", "Media control is off in BlueFerry: “blueferry media enable”.")
            if (status.available !== true)
                return I18n.trFor("iphoneStatus", "The iPhone's player is not reachable (it needs the Bluetooth LE link).")
            return I18n.trFor("iphoneStatus", "Start music on the iPhone and it will show up here.")
        }
    }
}
