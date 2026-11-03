import QtQuick
import qs.config
import qs.modules.theme

// Tailscale, mapped onto the VpnProvider contract. TailscaleService still does all the work;
// this file only translates.
VpnProvider {
    id: root

    providerId: "tailscale"
    label: "Tailscale"
    icon: Qt.resolvedUrl("../../assets/tailscale/tailscale-icon-white.svg")
    page: "TailscalePanel.qml"

    enabled: Config.system.tailscale.enabled
    showInBar: Config.system.tailscale.showInBar
    available: TailscaleService.available
    connected: TailscaleService.connected
    // Tailscale being up is not egress. It only owns the default route when an exit node is
    // set, so mesh-only Tailscale never takes part in a handoff.
    ownsDefaultRoute: TailscaleService.connected && TailscaleService.exitNodeId !== ""
    // isMutating, not isUpdating: a background read must not hold up a handoff.
    settled: !root.ownsDefaultRoute && !TailscaleService.isMutating
    lastError: TailscaleService.lastError

    // "Connected" alone is misleading: mesh access is not egress. An unavailable CLI reads
    // as "Off" here, as the hub always showed it; the page itself says "Not installed".
    statusLabel: !TailscaleService.connected ? "Off"
        : (root.ownsDefaultRoute ? "Exit node" : "Mesh only")
    statusTone: TailscaleService.connected ? "active" : "off"

    searchItems: [
        { label: "Tailscale", keywords: "vpn mesh tailnet wireguard remote", section: 11, subSection: "tailscale", subLabel: "VPN", icon: Icons.vpn, isIcon: true },
        { label: "Tailscale IP", keywords: "copy address ip magicdns dns", section: 11, subSection: "tailscale", subLabel: "VPN > Tailscale", icon: Icons.copy, isIcon: true },
        { label: "Exit Node", keywords: "route traffic vpn egress exit", section: 11, subSection: "tailscale", subLabel: "VPN > Tailscale", icon: Icons.globe, isIcon: true },
        { label: "Tailnet Profile", keywords: "account switch login profile", section: 11, subSection: "tailscale", subLabel: "VPN > Tailscale", icon: Icons.user, isIcon: true }
    ]

    // Loaded by URL rather than by type, so modules/services does not have to import the bar.
    trayComponent: Qt.createComponent(Qt.resolvedUrl("../bar/systray/TailscaleTrayItem.qml"))

    function up(options): bool {
        return TailscaleService.up();
    }
}
