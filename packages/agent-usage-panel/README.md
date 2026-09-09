# Agent usage panel

Adds a dashboard tab showing token usage, plan limits and reset windows for
coding agents installed locally.

<img src="assets/agent-usage-panel.png" alt="Agent usage dashboard" width="900">

## Install

```text
https://github.com/AspectHeat/ambxst-mods/tree/main/packages/agent-usage-panel
```

Paste that into **Settings → Mods**, or:

```bash
ambxst mods install https://github.com/AspectHeat/ambxst-mods/tree/main/packages/agent-usage-panel
ambxst mods enable aspect.agent-usage-panel
ambxst reload
```

Packages install disabled. Enabling builds a fresh source tree and takes effect
on the next `ambxst reload`. A failed build never touches the running shell.

## What it reads

The panel reads local provider data from `~/.claude`, `~/.codex`, the Cursor
configuration directory and the opencode database. Missing providers are
omitted. The usage refresh interval is configurable, with a default of 15
minutes.

It needs `python3` and reads and writes `~/.config/ambxst/agents.json` for the
default-agent selection.

Works with Ambxst `>=1.3.0 <1.4.0`.

## Permissions

This mod reads local coding-agent data and runs its bundled usage script with
your user permissions. Read the [manifest](ambxst.mod.json) before enabling it.

## License

MIT.
