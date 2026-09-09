# ambxst-mods

Mod packages for [Ambxst](https://github.com/Axenide/Ambxst) 1.3.x, ported out
of a long-running personal fork now that 1.3.0 ships a native mod manager.

## Packages

| Package | ID | What it does |
|---------|----|--------------|
| [`vpn-settings`](packages/vpn-settings) | `aspect.vpn-settings` | A VPN section in Settings with Tailscale and NordVPN pages, a provider handoff that moves the default route from one to the other, and an optional Tailscale item in the bar tray |
| [`agent-usage-panel`](packages/agent-usage-panel) | `aspect.agent-usage-panel` | A dashboard tab showing token usage, plan limits and reset windows for the coding agents installed locally, read from each provider's own on-disk data |

## Installing

Paste a package directory URL into **Settings → Mods**, or:

```bash
ambxst mods install https://github.com/AspectHeat/ambxst-mods/tree/main/packages/vpn-settings
ambxst mods enable aspect.vpn-settings
```

Packages install disabled. Enabling one builds a generation, and Ambxst has to
be restarted to load it. A failed build never touches the running shell.

### vpn-settings

Needs the `tailscale` and `nordvpn` CLIs for the respective pages; each provider
is independently gated, so one page works without the other installed. Adds
`tailscale`, `nordvpn` and `vpn` keys to the system config, and claims Settings
section id **11**.

Tailscale's exit-node controls need `tailscale set --operator=$USER` first,
otherwise every mutation needs a password prompt Ambxst cannot answer.

### agent-usage-panel

Needs `python3`. Reads whatever it finds among `~/.claude`, `~/.codex`, the
Cursor config directory and the opencode database, and shows nothing for
providers that are absent. The refresh interval is a mod setting, 15 minutes by
default.

## Settings section ids

Ambxst 1.3.2 allocates 0 through 10:

| id | Section | | id | Section |
|----|---------|-|----|---------|
| 0 | Network | | 6 | Binds |
| 1 | Bluetooth | | 7 | System |
| 2 | Mixer | | 8 | Compositor |
| 3 | AI | | 9 | Ambxst |
| 4 | Effects | | 10 | Mods |
| 5 | Theme | | | |

A mod that adds a section must claim a **new** id and register its panel under
the same id. Renumbering an existing section looks harmless in one package and
breaks as soon as a second one does it: the sidebar and the panel list drift
apart, and an entry opens somebody else's panel. Packages here allocate upward
from 11.

| id | Section | Package |
|----|---------|---------|
| 11 | VPN | `aspect.vpn-settings` |

`agent-usage-panel` needs no id, because it adds a dashboard tab rather than a
Settings section.

## Validating a change

```bash
./scripts/validate.sh                  # every package
./scripts/validate.sh packages/<name>  # one package
./scripts/compose.sh /tmp/tree         # just build the composed tree, to inspect
```

`AMBXST_SRC` selects the Ambxst source tree to check against, defaulting to
`~/.local/src/ambxst`. It must be 1.3.0 or newer, since the manifest schema
ships with the mod manager.

Per package, `validate.sh` checks that:

1. `ambxst.mod.json` validates against upstream's manifest schema.
2. Every declared operation source exists.
3. Overlays are honest. Replacing an existing base file requires `replace: true`
   and a matching `expectedSha256`, and `replace: true` against a target that
   does not exist is an error.
4. Every patch applies under `git apply --check --whitespace=error-all`.
5. The package's own `tests/run.sh` passes, if it has one.
6. `compatibility.testedBaseCommits` lists the base just tested.

Then across packages it composes one tree and does two things the per-package
checks cannot:

- **Patch collision.** Every patch is replayed onto that one tree in sequence.
  Patches that each apply alone can still collide, and composing is what the
  manager actually does.
- **Cross-component properties.** `check-props.py` confirms that every property
  a package assigns to another component actually exists on it.

That last check exists because of a real failure, and it is worth knowing about
if you are porting anything off a fork. `qmllint` cannot resolve Ambxst's `qs.*`
module imports, so it never learns what another component *is*, and never
notices that `TailscalePanel` assigned `toggleEnabled:` to a `PanelTitlebar`
that has no such property on stock 1.3.2. Lint was green, the manifest
validated, every patch applied, the generation built — and then the shell failed
to instantiate and the manager rolled back inside its startup health window.
Nothing broke, and nothing worked, and the only evidence was one line in a
Quickshell log.

An offscreen Quickshell would catch more, including missing singletons and bad
signal arities. It does not run: Ambxst's root object is a `PanelWindow` and the
offscreen Qt platform has no layer-shell backend, so it fails with `No
PanelWindow backend loaded` before reaching anything worth testing. That needs a
nested Wayland compositor.

## Tests

`vpn-settings` carries behavioural tests for its two NordVPN parsers, which are
`.pragma library` files with no QML imports and no side effects and so load in
plain node:

```bash
cd packages/vpn-settings && ./tests/run.sh
```

96 assertions across 35 captured CLI fixtures. No Quickshell, no compositor and
no NordVPN subscription required. Adding a fixture is adding a test: drop
`<name>.txt` next to a `<name>.expected.json`.

## Caveats

Mods run with your user permissions, exactly like the rest of Ambxst. The
`permissions` field in a manifest is review metadata shown before install, not a
sandbox. Read what a package does before enabling it.

These were extracted from a fork and shaped into packages, which meant leaving
some things behind. `vpn-settings` does not carry the fork's NordVPN tray
left-click override or its Settings deep-link retry timer, both of which rewrote
existing lines in shared files. Search results reach the VPN pages; an outside
caller opening Settings straight onto a provider page does not.

## License

MIT. See [LICENSE](LICENSE).
