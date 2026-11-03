import QtQuick
import qs.config
import qs.modules.theme

// NordVPN, mapped onto the VpnProvider contract. NordVpnService still does all the work;
// this file only translates.
//
// No trayComponent: NordVPN's own norduserd already puts an icon in the tray.
//
// options: { selection: "" | "Country" | "Country City", p2p: bool }
VpnProvider {
    id: root

    providerId: "nordvpn"
    label: "NordVPN"
    icon: Qt.resolvedUrl("../../assets/nordvpn/nordvpn.svg")
    iconMipmap: true
    page: "NordVpnPanel.qml"

    enabled: Config.system.nordvpn.enabled
    showInBar: Config.system.nordvpn.showInBar
    available: NordVpnService.available
    // Opens the page even when the CLI is missing, so the setup card can explain what to
    // install rather than the hub row being a dead end.
    canOpenPage: true
    connected: NordVpnService.connected
    // A NordVPN tunnel always carries the default route.
    ownsDefaultRoute: NordVpnService.connected
    // isMutating, not isUpdating: waiting on isUpdating would also wait out unrelated
    // background reads, stretching every handoff by a poll cycle.
    settled: !NordVpnService.connected && !NordVpnService.isMutating
    lastError: NordVpnService.lastError

    // Mirrors the provider page's state vocabulary.
    statusLabel: !NordVpnService.available ? "Not installed"
        : NordVpnService.permissionDenied ? "Permission denied"
        : !NordVpnService.daemonReachable ? "Daemon unavailable"
        : NordVpnService.needsLogin ? "Login required"
        : NordVpnService.connecting ? "Connecting…"
        : NordVpnService.disconnecting ? "Disconnecting…"
        : NordVpnService.connected ? "Connected" : "Off"
    statusTone: NordVpnService.connected ? "active"
        : (!NordVpnService.available || NordVpnService.needsLogin
            || NordVpnService.permissionDenied
            || !NordVpnService.daemonReachable
            ? "warning" : "off")

    searchItems: [
        { label: "NordVPN", keywords: "vpn privacy commercial nordlynx wireguard", section: 11, subSection: "nordvpn", subLabel: "VPN", icon: Icons.vpn, isIcon: true },
        // Deliberately not "Live VPN Servers": there is no per-server browsing and no
        // load metric, so that label advertised a feature that does not exist.
        { label: "VPN Locations", keywords: "country city location flag region server", section: 11, subSection: "nordvpn", subLabel: "VPN > NordVPN", icon: Icons.globe, isIcon: true },
        { label: "P2P VPN", keywords: "peer torrent speed optimized group", section: 11, subSection: "nordvpn", subLabel: "VPN > NordVPN", icon: Icons.lightning, isIcon: true },
        { label: "Quick Connect", keywords: "recommended nordvpn connect fastest", section: 11, subSection: "nordvpn", subLabel: "VPN > NordVPN", icon: Icons.lightning, isIcon: true }
    ]

    // Remember a country-level pick so Quick Connect and the primary toggle reuse it.
    // Nothing wrote this before, so "Quick Connect" always ignored the user's last choice.
    // City-level picks ("Country City") are deliberately not persisted - the CLI's own
    // recommended server within a country is the better default next time.
    function rememberSelection(selection): void {
        if (selection !== "" && !selection.includes(" "))
            Config.system.nordvpn.preferredCountry = selection;
    }

    function up(options): bool {
        const selection = options?.selection ?? "";
        root.rememberSelection(selection);
        return NordVpnService.connectTo(selection, options?.p2p ?? false);
    }

    // What was connected when the last handoff released the route, for restoreRoute().
    property string releasedSelection: ""
    property bool releasedP2p: false

    function releaseRoute(): bool {
        const selection = NordVpnService.requestedTarget;
        const p2p = NordVpnService.p2pPreferred;
        if (!NordVpnService.disconnect())
            return false;
        root.releasedSelection = selection;
        root.releasedP2p = p2p;
        return true;
    }

    function restoreRoute(): bool {
        return NordVpnService.connectTo(root.releasedSelection, root.releasedP2p);
    }

    // Already connected: a country/city change is a plain reconnect, NOT a handoff. Routing it
    // through the handoff phases made the coordinator see "connected" already true on its
    // first tick and declare success while the reconnect was still in flight.
    //
    // Returns true whenever it handled the request - including when the CLI was busy and
    // rejected it, which is what the coordinator always did here - so the coordinator does
    // not fall through into a handoff.
    function reconnectInPlace(options): bool {
        if (!NordVpnService.connected)
            return false;
        const selection = options?.selection ?? "";
        root.rememberSelection(selection);
        NordVpnService.connectTo(selection, options?.p2p ?? false);
        return true;
    }
}
