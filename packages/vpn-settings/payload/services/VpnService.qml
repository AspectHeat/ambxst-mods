pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.config

// Coordinates the VPN providers listed in VpnProviders.qml. Knows nothing about any CLI - it
// only reads the VpnProvider contract and serializes transitions between providers.
//
// Two rules this file exists to enforce:
//   1. handoffPhase is an ENUM and is never rendered. UI text comes from statusTextFor(),
//      which returns "" for any surface that is not the current handoff target. v1 rendered
//      a shared phase string everywhere, so the NordVPN page announced "Disconnecting
//      Tailscale...".
//   2. "connected" is not symmetric between providers, so a handoff is keyed on who owns
//      the DEFAULT ROUTE, not on who happens to be running. Only providers that own the
//      default route take part; a mesh-only Tailscale or a split-tunnel VPN is never touched.
Singleton {
    id: root

    // ---------------------------------------------------------------- observed facts
    // Every provider currently carrying the default route, in registry order. Normally zero or
    // one; more than one can only come from changes made outside Ambxst.
    readonly property var routeOwners: {
        const result = [];
        for (let i = 0; i < VpnProviders.providers.length; i++) {
            if (VpnProviders.providers[i].ownsDefaultRoute)
                result.push(VpnProviders.providers[i]);
        }
        return result;
    }

    // The first route owner's id, or "none". Kept for readers that want a single value (the
    // startup registration in shell.qml reads it to construct this singleton).
    readonly property string routeOwner: root.routeOwners.length > 0
        ? root.routeOwners[0].providerId : "none"
    readonly property string routeOwnerLabel: root.labelsOf(root.routeOwners)

    // Several providers can legitimately be connected at once (mesh + commercial egress).
    readonly property int connectedCount: {
        let count = 0;
        for (let i = 0; i < VpnProviders.providers.length; i++) {
            if (VpnProviders.providers[i].connected)
                count++;
        }
        return count;
    }

    // ---------------------------------------------------------------- handoff state
    // idle | confirming | disconnecting | connecting | failed
    property string handoffPhase: "idle"
    property string handoffTarget: ""
    property string lastError: ""

    // The providers whose route was released, so a failed handoff can offer to restore them
    // rather than silently mutating the network back.
    property var recoveryProviders: []
    // True while the "connecting" phase is a user-requested restore rather than a handoff.
    property bool restoring: false

    // Opaque to this file; handed to the target provider's up()/reconnectInPlace().
    property var pendingOptions: ({})
    property int elapsedTicks: 0

    readonly property bool busy: root.handoffPhase === "disconnecting"
        || root.handoffPhase === "connecting"
    readonly property bool awaitingConfirmation: root.handoffPhase === "confirming"

    // 500 ms ticks. Independently bounded per leg, unlike v1's single shared 25 s budget.
    readonly property int disconnectTimeoutTicks: 24  // 12 s
    readonly property int connectTimeoutTicks: 50     // 25 s

    // ---------------------------------------------------------------- lookups
    function providerFor(providerId): VpnProvider {
        return VpnProviders.byId(providerId);
    }

    function labelFor(providerId): string {
        const provider = root.providerFor(providerId);
        return provider ? provider.label : "";
    }

    function labelsOf(providers): string {
        const labels = [];
        for (const provider of providers)
            labels.push(provider.label);
        return labels.join(" and ");
    }

    function ownersOtherThan(providerId): var {
        return root.routeOwners.filter(provider => provider.providerId !== providerId);
    }

    // True when some provider other than this one carries the default route. Pages use it to
    // block their own egress changes, which would otherwise bypass the handoff confirmation.
    function routeOwnedByOther(providerId): bool {
        return root.ownersOtherThan(providerId).length > 0;
    }

    function otherOwnersLabel(providerId): string {
        return root.labelsOf(root.ownersOtherThan(providerId));
    }

    function recoveryList(): var {
        const result = [];
        for (const providerId of root.recoveryProviders) {
            const provider = root.providerFor(providerId);
            if (provider)
                result.push(provider);
        }
        return result;
    }

    // ---------------------------------------------------------------- text mapping
    // The direction guard. A surface only ever sees its own phase.
    function statusTextFor(providerId): string {
        if (root.handoffTarget !== providerId)
            return "";

        switch (root.handoffPhase) {
        case "confirming":
            return "Switch to " + root.labelFor(providerId) + "?";
        case "disconnecting": {
            // Name the provider still being released, so a multi-owner handoff reads honestly.
            const released = root.recoveryList();
            const pending = released.find(provider => !provider.settled) ?? released[0];
            return pending ? pending.releasingText : "";
        }
        case "connecting": {
            const provider = root.providerFor(providerId);
            if (root.restoring && provider)
                return provider.restoringText;
            return "Connecting " + root.labelFor(providerId) + "…";
        }
        case "failed":
            return root.lastError !== "" ? root.lastError : "Switch failed";
        default:
            return "";
        }
    }

    // What the confirmation says will happen to the current route owners.
    function releaseConsequenceFor(providerId): string {
        return root.ownersOtherThan(providerId).map(provider => provider.releaseConsequence).join(" ");
    }

    function restoreActionText(): string {
        const providers = root.recoveryList();
        if (providers.length === 1)
            return providers[0].restoreActionText;
        return "Reconnect " + root.labelsOf(providers);
    }

    // ---------------------------------------------------------------- lifecycle
    function resetState(): void {
        handoffTimer.stop();
        root.handoffPhase = "idle";
        root.handoffTarget = "";
        root.lastError = "";
        root.recoveryProviders = [];
        root.restoring = false;
        root.elapsedTicks = 0;
    }

    // Called when a provider page mounts, so a stale phase or error from an earlier attempt
    // cannot persist on screen. v1 rendered lastError indefinitely.
    function clearTransient(): void {
        // Also preserved while confirming: NordVpnPanel calls this on mount, and a handoff
        // started from the hub would otherwise be cancelled the moment the page opened.
        if (root.busy || root.awaitingConfirmation)
            return;
        root.resetState();
    }

    function requestProvider(targetId, options): void {
        // Also ignored while awaiting confirmation: otherwise a second country click
        // silently swapped the pending options while the prompt still named the first one.
        if (root.busy || root.awaitingConfirmation || !targetId)
            return;
        const target = root.providerFor(targetId);
        if (!target)
            return;

        root.pendingOptions = options ?? {};
        root.lastError = "";
        root.recoveryProviders = [];
        root.restoring = false;

        // Already connected and the provider can change its connection in place (NordVPN
        // switching country): a plain reconnect, NOT a handoff. Routing it through the
        // handoff phases made handoffTimer see the target connected on its first tick and
        // declare success while the reconnect was still in flight.
        if (target.connected && target.reconnectInPlace(root.pendingOptions))
            return;

        const others = root.ownersOtherThan(targetId);

        // Only a no-op when the target ALREADY owns egress alone. If Tailscale is up
        // mesh-only while NordVPN owns the route, "switch to Tailscale" is a real request:
        // release NordVPN so traffic goes direct and the tailnet keeps working. Returning on
        // "connected" alone made that click do nothing at all.
        if (target.ownsDefaultRoute && others.length === 0)
            return;

        root.handoffTarget = targetId;

        // Nothing else owns egress: connect directly.
        if (others.length === 0) {
            root.connectTarget(targetId);
            return;
        }

        if (Config.system.vpn.handoffPolicy === "confirm") {
            root.handoffPhase = "confirming";
            return;
        }
        root.beginHandoff();
    }

    function confirmHandoff(): void {
        if (root.handoffPhase !== "confirming")
            return;
        root.beginHandoff();
    }

    function cancelHandoff(): void {
        // Only legal before anything has been released. Resets directly: clearTransient()
        // deliberately leaves a pending confirmation alone, so going through it made Cancel
        // (and the confirmation timeout) do nothing.
        if (root.handoffPhase !== "confirming")
            return;
        root.resetState();
    }

    function beginHandoff(): void {
        // Every current owner except the target is released, and every one of them is
        // remembered for an explicit restore.
        const others = root.ownersOtherThan(root.handoffTarget);
        root.recoveryProviders = others.map(provider => provider.providerId);
        root.restoring = false;
        root.handoffPhase = "disconnecting";
        root.elapsedTicks = 0;

        if (others.length === 0) {
            // The owner went away while the prompt was open; nothing left to release.
            root.connectTarget(root.handoffTarget);
            return;
        }

        // A provider rejects a mutation while one is already in flight. Detect that instead
        // of showing "Disconnecting..." for 12 s against a command that never ran.
        for (const provider of others) {
            if (!provider.releaseRoute()) {
                root.fail(provider.releaseFailedText);
                return;
            }
        }

        handoffTimer.restart();
    }

    function connectTarget(targetId): void {
        const target = root.providerFor(targetId);
        root.handoffTarget = targetId;
        root.restoring = false;
        root.handoffPhase = "connecting";
        root.elapsedTicks = 0;

        // Already connected: the handoff's purpose was releasing the OTHER provider, which
        // has now happened. Issuing `tailscale up` again would be a pointless mutation and
        // the timer would succeed on its first tick anyway.
        if (!target || target.connected) {
            root.succeed();
            return;
        }

        if (!target.up(root.pendingOptions)) {
            // Covers Tailscale needing a browser login as well as a busy provider: either way
            // there is no mutation to wait on, so say so instead of timing out.
            root.fail("Could not connect " + target.label
                + " right now. It may be busy or need you to log in.");
            return;
        }

        handoffTimer.restart();
    }

    function succeed(): void {
        root.resetState();
    }

    function fail(message): void {
        handoffTimer.stop();
        root.lastError = String(message ?? "") || "VPN switch failed";
        root.handoffPhase = "failed";
        root.restoring = false;
        root.elapsedTicks = 0;
    }

    // Explicit user recovery after a failed handoff. Never automatic - an unexpected
    // network mutation is worse than a visible failure. Restores every released provider.
    function recover(): void {
        const providers = root.recoveryList();
        if (providers.length === 0)
            return;

        root.lastError = "";
        root.handoffTarget = providers[0].providerId;
        root.handoffPhase = "connecting";
        root.restoring = true;
        root.elapsedTicks = 0;

        // One that still owns the route was never released (or already came back); restoring
        // it again would be a pointless mutation.
        const pending = providers.filter(provider => !provider.ownsDefaultRoute);
        if (pending.length === 0) {
            root.succeed();
            return;
        }

        for (const provider of pending) {
            if (!provider.restoreRoute()) {
                root.fail("Could not reconnect " + provider.label
                    + " right now. It may be busy or need you to log in.");
                return;
            }
        }

        handoffTimer.restart();
    }

    function dismissFailure(): void {
        if (root.handoffPhase !== "failed")
            return;
        root.resetState();
    }

    // Safety net: a confirmation can be requested from a surface that has no confirm UI
    // mounted (the tray popup can be dismissed mid-question). Auto-cancel rather than
    // leaving the coordinator wedged in "confirming" for the rest of the session.
    Timer {
        id: confirmTimeout
        interval: 30000
        repeat: false
        running: root.awaitingConfirmation
        onTriggered: if (root.awaitingConfirmation) root.cancelHandoff()
    }

    Timer {
        id: handoffTimer
        interval: 500
        repeat: true

        onTriggered: {
            root.elapsedTicks++;

            if (root.handoffPhase === "disconnecting") {
                const unsettled = root.recoveryList().filter(provider => !provider.settled);
                if (unsettled.length === 0) {
                    root.connectTarget(root.handoffTarget);
                    return;
                }
                if (root.elapsedTicks > root.disconnectTimeoutTicks)
                    root.fail(unsettled[0].releaseTimedOutText);
                return;
            }

            if (root.handoffPhase === "connecting") {
                // A restore is done when every restored provider carries the route again; a
                // handoff is done when the target is connected (mesh-only counts for
                // Tailscale - the point was releasing the other provider).
                const waiting = root.restoring
                    ? root.recoveryList().filter(provider => !provider.ownsDefaultRoute)
                    : [root.providerFor(root.handoffTarget)].filter(provider => provider && !provider.connected);
                if (waiting.length === 0) {
                    root.succeed();
                    return;
                }
                for (const provider of waiting) {
                    if (provider.lastError !== "") {
                        root.fail(provider.lastError);
                        return;
                    }
                }
                if (root.elapsedTicks > root.connectTimeoutTicks)
                    root.fail("Timed out connecting " + waiting[0].label);
                return;
            }

            handoffTimer.stop();
        }
    }
}
