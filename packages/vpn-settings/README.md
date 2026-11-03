# VPN settings

Adds a VPN section to Ambxst Settings with Tailscale and NordVPN pages, a
provider handoff for moving the default route between them, and an optional
Tailscale item in the bar tray.

<img src="assets/vpn-settings.png" alt="VPN provider settings" width="900">

<p>
<img src="assets/nordvpn.png" alt="NordVPN settings" width="900">
</p>

<p>
<img src="assets/tailscale-redacted.png" alt="Tailscale settings with private details redacted" width="900">
</p>

The Tailscale screenshot has network addresses, DNS details, device names and
other fleet information redacted.

## Install

```text
https://github.com/AspectHeat/ambxst-mods/tree/main/packages/vpn-settings
```

Paste that into **Settings → Mods**, or:

```bash
ambxst mods install https://github.com/AspectHeat/ambxst-mods/tree/main/packages/vpn-settings
ambxst mods enable aspect.vpn-settings
ambxst reload
```

Packages install disabled. Enabling builds a fresh source tree and takes effect
on the next `ambxst reload`. A failed build never touches the running shell.

## Requirements

No VPN CLI is required to enable the mod. Each provider page detects its own
CLI and shows "Not installed" when it is missing, so you only need the
providers you use. The NordVPN page has a setup button that installs and
configures the `nordvpn` CLI for you.

Works with Ambxst `>=1.3.0 <1.4.0`.

## Switching providers

Only a provider that carries your internet traffic (the default route) takes
part in a switch. Tailscale counts only while it uses an exit node; mesh-only
Tailscale is never touched. Switching from a Tailscale exit node to NordVPN
clears the exit node and leaves the tailnet connected. If a switch fails, the
VPN page offers to restore what was there before; it never does so on its own.

## Adding a provider

Providers are listed in `modules/services/VpnProviders.qml`. A provider is a
`VpnProvider` (see `modules/services/VpnProvider.qml` for the full contract),
usually a thin adapter over the provider's own service singleton. It supplies:

- identity: `providerId`, `label`, `icon`, and `page`, the settings page the
  VPN hub loads for it;
- state: `enabled`, `available`, `connected`, `ownsDefaultRoute`, `settled`,
  `lastError`, plus `statusLabel` and `statusTone` for its hub card;
- `searchItems` for Settings search, and an optional `trayComponent`;
- actions: `up(options)`, `releaseRoute()`, `restoreRoute()` and, optionally,
  `reconnectInPlace(options)`. Each returns `false` when nothing was started.

To register it, a second mod overlays its provider file into
`modules/services/` and adds one line to the registry with a patch, directly
above the end marker:

```diff
         NordVpnProvider {},
+        WireGuardProvider {},
         // vpn-providers: end
```

Ambxst merges inserts from several mods at the same anchor, so providers from
different mods do not conflict. Declare `aspect.vpn-settings` as a dependency
so the registry exists before your patch applies.

## Permissions

This mod runs the Tailscale and NordVPN CLIs with your user permissions. Read
the [manifest](ambxst.mod.json) before enabling it.

## License

MIT.
