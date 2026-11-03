pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import qs.config
import qs.modules.components
import qs.modules.services
import qs.modules.theme

// One hub row for one VPN provider. Everything it shows comes from the VpnProvider contract,
// so the hub draws every provider the same way.
StyledRect {
    id: root

    required property VpnProvider provider

    signal clicked

    Layout.fillWidth: true
    Layout.preferredHeight: 56
    variant: mouseArea.containsMouse ? "focus" : "pane"
    radius: Styling.radius(0)

    RowLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 12

        StyledRect {
            Layout.preferredWidth: 32
            Layout.preferredHeight: 32
            variant: root.provider.connected ? "primary" : "internalbg"
            radius: Styling.radius(2)

            Image {
                anchors.centerIn: parent
                width: 20
                height: 20
                source: root.provider.icon
                sourceSize: Qt.size(40, 40)
                smooth: true
                mipmap: root.provider.iconMipmap

                layer.enabled: true
                layer.effect: MultiEffect {
                    colorization: 1
                    colorizationColor: root.provider.connected
                        ? Styling.srItem("primary") : Colors.overBackground
                }
            }
        }

        Text {
            text: root.provider.label
            font.family: Config.theme.font
            font.pixelSize: Styling.fontSize(0)
            font.bold: true
            color: Colors.overBackground
        }

        Text {
            text: root.provider.statusLabel
            font.family: Config.theme.font
            font.pixelSize: Styling.fontSize(-2)
            color: root.provider.statusTone === "active" ? Styling.srItem("overprimary")
                : (root.provider.statusTone === "warning" ? Colors.warning : Colors.overSurfaceVariant)
        }

        Item {
            Layout.fillWidth: true
        }

        Text {
            text: Icons.caretRight
            font.family: Icons.font
            font.pixelSize: 20
            color: Colors.overSurfaceVariant
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        // Every card is inert during a handoff, so a second network mutation cannot be
        // started while one is in flight.
        enabled: root.provider.canOpenPage && !VpnService.busy
            && !VpnService.awaitingConfirmation
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.clicked()
    }
}
