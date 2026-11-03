import QtQuick

// The contract every VPN provider implements. VpnService, the VPN hub, the bar tray and the
// Settings search only ever talk to providers through this type, so adding a provider means
// writing one of these and adding one line to VpnProviders.qml - nothing else.
//
// An adapter wraps the provider's own service singleton; it does not replace it. Keep CLI
// handling in the service and only the mapping onto this vocabulary here.
QtObject {
    id: root

    // ---------------------------------------------------------------- identity
    // Stable, lowercase. Used as the Settings subsection id and as the handoff key. Called
    // providerId because `id` is reserved in QML.
    property string providerId: ""
    property string label: ""
    // Monochrome icon; the hub colourises it. Use Qt.resolvedUrl() where you assign it so
    // the path resolves against your own file.
    property url icon
    // Some raster-ish SVGs look soft at 20 px without this. Purely cosmetic.
    property bool iconMipmap: false
    // Settings page, loaded by VpnPanel. A bare file name resolves next to VpnPanel.qml
    // (modules/widgets/dashboard/controls); anything else should be an absolute URL. The page
    // may expose maxContentWidth, showBackButton, signal backRequested() and
    // positionAtBeginning(); all are optional.
    property string page: ""

    // ---------------------------------------------------------------- observed state
    // Normally reads the provider's own Config.system.<id>.enabled.
    property bool enabled: false
    // Whether the bar should draw trayComponent. Normally Config.system.<id>.showInBar.
    property bool showInBar: false
    // The CLI/daemon is installed.
    property bool available: false
    // Whether the hub card opens the page. Defaults to availability; a provider whose page
    // explains how to install it should set this true.
    property bool canOpenPage: root.available
    property bool connected: false
    // True only while this provider carries the machine's default route (egress). This, not
    // `connected`, decides who takes part in a handoff: a mesh-only or split-tunnel VPN is
    // never touched.
    property bool ownsDefaultRoute: false
    // True when this provider no longer owns the default route and has no mutation in flight.
    // The coordinator waits on this after releaseRoute().
    property bool settled: !root.ownsDefaultRoute
    property string lastError: ""

    // Hub card text and its colour: "active" | "warning" | "off".
    property string statusLabel: ""
    property string statusTone: "off"

    // Handoff wording. Defaults suit a provider whose release is a full disconnect.
    property string releasingText: "Disconnecting " + root.label + "…"
    property string releaseConsequence: root.label
        + " is carrying your internet traffic right now and will be turned off first."
    property string restoreActionText: "Reconnect " + root.label

    // SettingsIndex entries in its usual shape, with section 11 and subSection = id.
    property var searchItems: []

    // Optional bar tray item. Instantiated with `bar` set; null means no tray item.
    property Component trayComponent: null

    // ---------------------------------------------------------------- actions
    // Each returns false when nothing was started (busy, logged out, not installed), so the
    // coordinator can fail fast instead of waiting out a timeout. `options` is opaque to the
    // coordinator and only meaningful to the provider that receives it.
    function up(options): bool {
        return false;
    }

    // Stop carrying the default route. Disconnecting is the usual way; a provider that can
    // drop egress while staying up for other purposes should do that instead.
    function releaseRoute(): bool {
        return false;
    }

    // Undo releaseRoute() after a failed handoff. Only ever called on explicit user request.
    function restoreRoute(): bool {
        return false;
    }

    // Change an existing connection (for example a different country) without a handoff.
    // false means "not supported", and the coordinator treats the request as a normal one.
    function reconnectInPlace(options): bool {
        return false;
    }
}
