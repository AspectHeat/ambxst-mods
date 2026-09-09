#!/usr/bin/env bash
# Compose packages onto a scratch copy of the Ambxst source, the way the mod
# manager does: all overlays, then all patches, per package in argument order.
#
#   compose.sh <dest-dir> [package-dir ...]
#
# With no package arguments every package under packages/ is used, sorted.
# SKIP_PATCH is a space-separated list of patch basenames to leave out, which
# is how a regression test reproduces the state before a fix.
set -euo pipefail

AMBXST_SRC="${AMBXST_SRC:-$HOME/.local/src/ambxst}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dest="${1:?usage: compose.sh <dest-dir> [package-dir ...]}"
shift || true

git -C "$AMBXST_SRC" rev-parse --git-dir >/dev/null 2>&1 || { echo "no Ambxst tree at $AMBXST_SRC" >&2; exit 2; }

if [[ $# -gt 0 ]]; then packages=("$@")
else mapfile -t packages < <(find "$repo_root/packages" -mindepth 1 -maxdepth 1 -type d | sort); fi

rm -rf "$dest"; mkdir -p "$dest"
git -C "$AMBXST_SRC" archive HEAD | tar -x -C "$dest"
git -C "$dest" init -q

for pkg in "${packages[@]}"; do
  # absolute, because git -C "$dest" resolves patch paths from $dest
  pkg="$(cd "$pkg" && pwd)"
  python3 - "$pkg" "$dest" <<'OVPY'
import json, os, shutil, sys
pkg, dest = sys.argv[1], sys.argv[2]
m = json.load(open(os.path.join(pkg, "ambxst.mod.json")))
for op in m["operations"]:
    if op["type"] == "overlay":
        t = os.path.join(dest, op["target"])
        os.makedirs(os.path.dirname(t), exist_ok=True)
        shutil.copy(os.path.join(pkg, op["source"]), t)
OVPY
  while IFS= read -r rel; do
    [[ -z "$rel" ]] && continue
    base="$(basename "$rel")"
    if [[ " ${SKIP_PATCH:-} " == *" $base "* ]]; then
      echo "  skipping $base" >&2
      continue
    fi
    git -C "$dest" apply --whitespace=nowarn "$pkg/$rel"
  done < <(python3 -c '
import json,sys,os
m=json.load(open(os.path.join(sys.argv[1],"ambxst.mod.json")))
print("\n".join(op["source"] for op in m["operations"] if op["type"]=="patch"))' "$pkg")
done
rm -rf "$dest/.git"
