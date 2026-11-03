pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

// The fixed list of VPN providers. Order here is the order of the hub cards, the tray items
// and the Settings search entries.
//
// Each provider is one child line between the markers. Another mod adds its own provider with
// a one-line patch that inserts `MyProvider {}` directly above the end marker; Ambxst's patch
// merger keeps every mod's insert at the same anchor, so several such mods coexist in load
// order. No folder scanning.
Singleton {
    id: root

    default property list<VpnProvider> providers

    // vpn-providers: add one line per provider below
    TailscaleProvider {}
    NordVpnProvider {}
    // vpn-providers: end

    readonly property var enabledProviders: {
        const result = [];
        for (let i = 0; i < root.providers.length; i++) {
            if (root.providers[i].enabled)
                result.push(root.providers[i]);
        }
        return result;
    }

    readonly property bool anyEnabled: root.enabledProviders.length > 0

    // Search entries of every enabled provider, in registry order.
    readonly property var searchItems: {
        let result = [];
        for (const provider of root.enabledProviders)
            result = result.concat(provider.searchItems);
        return result;
    }

    function byId(providerId): VpnProvider {
        for (let i = 0; i < root.providers.length; i++) {
            if (root.providers[i].providerId === providerId)
                return root.providers[i];
        }
        return null;
    }
}
