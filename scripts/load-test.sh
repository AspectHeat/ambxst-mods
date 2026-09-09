#!/usr/bin/env bash
# Compose every package onto a scratch copy of the Ambxst source and load the
# result with an offscreen Quickshell, to catch what qmllint cannot.
#
# qmllint cannot resolve Quickshell's `qs.*` modules, so it never sees a
# property that does not exist on another component. That class of error only
# appears when the QML engine actually instantiates the tree, which is how
# "Cannot assign to non-existent property" gets through a green lint and only
# fails inside the mod manager's startup health window.
#
# Exit: 0 the composed tree loads, 1 it does not, 2 the harness could not run.
set -uo pipefail

AMBXST_SRC="${AMBXST_SRC:-$HOME/.local/src/ambxst}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

red()   { printf '\033[0;31m%s\033[0m\n' "$1"; }
green() { printf '\033[0;32m%s\033[0m\n' "$1"; }
blue()  { printf '\033[0;34m%s\033[0m\n' "$1"; }

command -v qs >/dev/null || { red "quickshell (qs) required"; exit 2; }
git -C "$AMBXST_SRC" rev-parse --git-dir >/dev/null 2>&1 || { red "no Ambxst tree at $AMBXST_SRC"; exit 2; }

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
git -C "$AMBXST_SRC" archive HEAD | tar -x -C "$scratch"

if [[ $# -gt 0 ]]; then packages=("$@")
else mapfile -t packages < <(find "$repo_root/packages" -mindepth 1 -maxdepth 1 -type d | sort); fi

blue "composing $(printf '%s ' "$(for p in "${packages[@]}"; do basename "$p"; done)")onto $(cat "$AMBXST_SRC/version")"
for pkg in "${packages[@]}"; do
  # overlays first, then patches, matching the manager
  while IFS=$'\t' read -r src target; do
    [[ -z "$src" ]] && continue
    mkdir -p "$scratch/$(dirname "$target")"
    cp "$pkg/$src" "$scratch/$target"
  done < <(python3 -c '
import json,sys
m=json.load(open(sys.argv[1]))
for op in m.get("operations",[]):
    if op.get("type")=="overlay": print(op["source"]+"\t"+op["target"])
' "$pkg/ambxst.mod.json")
  while IFS= read -r src; do
    [[ -z "$src" ]] && continue
    if ! (cd "$scratch" && git init -q 2>/dev/null; git -C "$scratch" apply --whitespace=nowarn "$pkg/$src"); then
      red "  failed to apply $(basename "$pkg")/$(basename "$src")"; exit 1
    fi
  done < <(python3 -c '
import json,sys
m=json.load(open(sys.argv[1]))
for op in m.get("operations",[]):
    if op.get("type")=="patch": print(op["source"])
' "$pkg/ambxst.mod.json")
done
rm -rf "$scratch/.git"
green "  composed"

log="$(mktemp)"
blue "loading offscreen"
# A sandbox HOME, not XDG_* alone: Ambxst hard-codes several $HOME/.cache/ambxst
# and $HOME/.local/share/ambxst paths that XDG variables do not redirect, and
# this must not touch the running instance's state, clipboard stores or mods.
sandbox="$(mktemp -d)"
mkdir -p "$sandbox/.config" "$sandbox/.cache" "$sandbox/.local/share" "$sandbox/.local/state"
QT_QPA_PLATFORM=offscreen \
HOME="$sandbox" \
XDG_CONFIG_HOME="$sandbox/.config" \
XDG_CACHE_HOME="$sandbox/.cache" \
XDG_DATA_HOME="$sandbox/.local/share" \
XDG_STATE_HOME="$sandbox/.local/state" \
  timeout 60 qs -p "$scratch/shell.qml" >"$log" 2>&1 &
qspid=$!
for _ in $(seq 1 60); do
  grep -q 'Configuration Loaded' "$log" 2>/dev/null && break
  grep -q 'Failed to load configuration' "$log" 2>/dev/null && break
  kill -0 "$qspid" 2>/dev/null || break
  sleep 0.5
done
kill "$qspid" 2>/dev/null; wait "$qspid" 2>/dev/null
rm -rf "$sandbox"

if grep -q 'Failed to load configuration' "$log"; then
  red "LOAD FAILED"
  grep -E 'ERROR|caused by' "$log" | head -20 | sed 's/^/  /'
  rm -f "$log"; exit 1
fi
if grep -q 'Configuration Loaded' "$log"; then
  green "LOAD OK: the composed tree instantiates"
  # These do not fail the load, but a non-existent property or an undefined
  # singleton in a mod's own file is a defect worth seeing.
  if grep -qE 'non-existent property|ReferenceError' "$log"; then
    blue "  runtime findings:"
    grep -E 'non-existent property|ReferenceError' "$log" | sort -u | head -12 | sed 's/^/    /'
  fi
  rm -f "$log"; exit 0
fi
red "INCONCLUSIVE: neither success nor failure marker appeared"
tail -20 "$log" | sed 's/^/  /'
rm -f "$log"; exit 1
