pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.config
import qs.modules.components
import qs.modules.services
import qs.modules.theme

Item {
    id: root

    property int maxContentWidth: 480
    property string currentSection: ""
    readonly property int contentWidth: Math.min(width, maxContentWidth)

    ColumnLayout {
        visible: root.currentSection === ""
        width: root.contentWidth
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 8

        PanelTitlebar {
            Layout.fillWidth: true
            title: "VPN"
        }

        Text {
            Layout.fillWidth: true
            text: "Providers"
            font.family: Config.theme.font
            font.pixelSize: Styling.fontSize(-2)
            font.weight: Font.Medium
            color: Colors.overSurfaceVariant
        }

        // One card per enabled provider, in registry order (VpnProviders.qml).
        Repeater {
            model: VpnProviders.providers

            ProviderCard {
                required property VpnProvider modelData

                provider: modelData
                visible: modelData.enabled
                onClicked: root.currentSection = modelData.providerId
            }
        }

        // Route-owner strip. Appears only when something actually owns egress - Tailscale
        // merely running is not egress unless an exit node is set (VpnService.routeOwner).
        StyledRect {
            Layout.fillWidth: true
            visible: VpnService.routeOwner !== "" && VpnService.routeOwner !== "none"
                && VpnService.handoffPhase === "idle"
            implicitHeight: 34
            variant: "internalbg"
            radius: Styling.radius(4)

            Text {
                anchors.centerIn: parent
                width: parent.width - 20
                text: VpnService.labelFor(VpnService.routeOwner) + " currently owns the default route"
                    + (VpnService.bothConnected ? " · both providers connected" : "")
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(-2)
                color: Colors.overSurfaceVariant
            }
        }

    }

    // Floating, and a sibling of BOTH the hub column and the provider Loaders, because a
    // handoff can be started from the hub or from either provider page - all three render
    // inside this item. When the confirm controls lived in the hub column (hidden whenever
    // currentSection !== ""), confirming a switch from a provider page was impossible.
    VpnHandoffCard {
        // Above the provider Loaders. Declaration order alone is not enough: they fill the
        // panel, so with default z they painted OVER this card and
        // a confirmation started from a provider page was still unanswerable.
        z: 1
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: 8
        width: root.contentWidth
    }

    // Drop any stale phase or error from a previous visit so it cannot linger on screen.
    // Preserves an in-flight or awaiting-confirmation handoff (see VpnService.clearTransient).
    Component.onCompleted: VpnService.clearTransient()

    // Compile every enabled provider page in the background as soon as the hub mounts, then
    // retain it. The previous single Loader started only after a provider click and destroyed
    // its item on every switch, so the user watched Tailscale construct itself in stages and
    // lost local scroll/expanded state. Visibility changes are now navigation-only.
    Repeater {
        model: VpnProviders.providers

        Loader {
            id: pageLoader

            required property VpnProvider modelData
            property bool positioned: false
            readonly property bool selected: root.currentSection === pageLoader.modelData.providerId

            function positionOnFirstVisit(): void {
                if (pageLoader.positioned || !pageLoader.item)
                    return;
                pageLoader.positioned = true;
                // The retained page may have compiled while its Loader was hidden and had no
                // usable viewport geometry. Wait until this visit has made it visible before
                // positioning. Optional: a page without the function is simply not positioned.
                const page = pageLoader.item;
                if (typeof page.positionAtBeginning === "function")
                    Qt.callLater(() => page.positionAtBeginning());
            }

            anchors.fill: parent
            active: pageLoader.modelData.enabled && pageLoader.modelData.page !== ""
            visible: pageLoader.selected
            source: pageLoader.modelData.page
            // Background preload stays asynchronous. Selecting this provider flips the Loader
            // synchronous, forcing any in-progress incubation to finish before it is shown.
            asynchronous: !pageLoader.selected

            onLoaded: {
                if (item) {
                    if ("maxContentWidth" in item)
                        item.maxContentWidth = root.maxContentWidth;
                    if ("showBackButton" in item)
                        item.showBackButton = true;
                    if (pageLoader.selected)
                        pageLoader.positionOnFirstVisit();
                }
            }

            Connections {
                target: root

                // Compared directly rather than through `selected`, whose binding may not have
                // re-evaluated yet when this handler runs.
                function onCurrentSectionChanged() {
                    if (root.currentSection === pageLoader.modelData.providerId)
                        pageLoader.positionOnFirstVisit();
                }
            }

            Connections {
                target: pageLoader.item
                ignoreUnknownSignals: true

                function onBackRequested() {
                    root.currentSection = "";
                }
            }
        }
    }
}
