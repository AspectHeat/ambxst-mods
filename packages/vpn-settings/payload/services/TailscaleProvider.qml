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

    // Releasing the route clears the exit node instead of running `tailscale down`, so the
    // tailnet stays up through a handoff. "Allow LAN access" is never touched.
    releasingText: "Clearing Tailscale exit node…"
    releaseFailedText: "Could not clear the Tailscale exit node right now. Try again."
    releaseTimedOutText: "Timed out clearing the Tailscale exit node"
    releaseConsequence: "Tailscale is sending your internet traffic through an exit node right now"
        + " and will stop using it first. Your tailnet stays connected."
    restoreActionText: "Restore Tailscale exit node"
    restoringText: "Restoring Tailscale exit node…"

    // The exit node released by the last handoff, for restoreRoute().
    property string releasedExitNode: ""

    // TailscaleService's set/clear functions return nothing, but they go through runMutation,
    // which starts the command unless one of exactly these holds. Checking the same guard
    // first is what lets this return an honest "started".
    function canMutate(): bool {
        return TailscaleService.available && TailscaleService.enabled && !TailscaleService.isMutating;
    }

    function up(options): bool {
        return TailscaleService.up();
    }

    function releaseRoute(): bool {
        if (!root.canMutate())
            return false;
        root.releasedExitNode = TailscaleService.exitNodeId;
        TailscaleService.clearExitNode();
        return true;
    }

    function restoreRoute(): bool {
        if (root.releasedExitNode === "" || !root.canMutate())
            return false;
        TailscaleService.setExitNode(root.releasedExitNode);
        return true;
    }
}
