#!/usr/bin/env bash
# Validate mod packages against a real Ambxst source tree.
#
# Checks per package:
#   1. ambxst.mod.json parses and validates against upstream's manifest schema
#   2. every declared operation source exists
#   3. every patch applies to the base with git apply --check --whitespace=error-all
#   4. reports the base commit tested, for compatibility.testedBaseCommits
#
# Exit: 0 all packages pass, 1 a package failed, 2 the harness could not run.
set -uo pipefail

AMBXST_SRC="${AMBXST_SRC:-$HOME/.local/src/ambxst}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

red()   { printf '\033[0;31m%s\033[0m\n' "$1"; }
green() { printf '\033[0;32m%s\033[0m\n' "$1"; }
blue()  { printf '\033[0;34m%s\033[0m\n' "$1"; }
warn()  { printf '\033[1;33m%s\033[0m\n' "$1"; }

git -C "$AMBXST_SRC" rev-parse --git-dir >/dev/null 2>&1 || { red "no Ambxst git tree at $AMBXST_SRC (set AMBXST_SRC)"; exit 2; }
command -v python3 >/dev/null || { red "python3 required"; exit 2; }
python3 -c 'import jsonschema' 2>/dev/null || { red "python jsonschema required"; exit 2; }

SCHEMA="$AMBXST_SRC/docs/mods/manifest.schema.json"
[[ -f "$SCHEMA" ]] || { red "no manifest schema at $SCHEMA (is Ambxst >= 1.3.0?)"; exit 2; }

BASE_COMMIT="$(git -C "$AMBXST_SRC" rev-parse HEAD)"
BASE_VERSION="$(cat "$AMBXST_SRC/version" 2>/dev/null || echo unknown)"
if [[ -n "$(git -C "$AMBXST_SRC" status --porcelain)" ]]; then
  warn "! $AMBXST_SRC is dirty; patch checks run against modified files"
fi
blue "base: Ambxst $BASE_VERSION at $BASE_COMMIT"
echo

if [[ $# -gt 0 ]]; then
  packages=("$@")
else
  mapfile -t packages < <(find "$repo_root/packages" -mindepth 1 -maxdepth 1 -type d | sort)
fi
[[ ${#packages[@]} -gt 0 ]] || { warn "no packages found"; exit 0; }

fail=0
for pkg in "${packages[@]}"; do
  name="$(basename "$pkg")"
  blue "== $name"
  manifest="$pkg/ambxst.mod.json"
  if [[ ! -f "$manifest" ]]; then red "  no ambxst.mod.json"; fail=1; continue; fi

  if ! python3 - "$manifest" "$SCHEMA" <<'PY'
import json, sys, jsonschema
manifest, schema = sys.argv[1], sys.argv[2]
try:
    inst = json.load(open(manifest))
except json.JSONDecodeError as e:
    print(f"  manifest is not valid JSON: {e}"); sys.exit(1)
try:
    jsonschema.validate(inst, json.load(open(schema)))
except jsonschema.ValidationError as e:
    print(f"  schema error at {list(e.path)}: {e.message}"); sys.exit(1)
print(f"  manifest ok: {inst['id']} {inst['version']} (range {inst['compatibility']['ambxst']})")
PY
  then red "  manifest FAILED"; fail=1; continue; fi

  # operation sources must exist
  missing=0
  while IFS= read -r src; do
    [[ -z "$src" ]] && continue
    if [[ ! -f "$pkg/$src" ]]; then red "  missing operation source: $src"; missing=1; fi
  done < <(python3 -c '
import json,sys
m=json.load(open(sys.argv[1]))
for op in m.get("operations",[]):
    if op.get("source"): print(op["source"])
' "$manifest")
  [[ $missing -eq 0 ]] || { fail=1; continue; }

  # an overlay onto an existing file needs replace:true and the current sha256,
  # otherwise the manager refuses it and a base change would silently clobber
  # newer upstream code
  if ! python3 - "$manifest" "$AMBXST_SRC" <<'OVERLAYPY'
import json, sys, os, hashlib
manifest, src = sys.argv[1], sys.argv[2]
m = json.load(open(manifest))
bad = False
for op in m.get("operations", []):
    if op.get("type") != "overlay":
        continue
    target = op.get("target")
    if not target:
        print(f"  overlay with no target: {op.get('source')}"); bad = True; continue
    path = os.path.join(src, target)
    exists = os.path.isfile(path)
    if exists and not op.get("replace"):
        print(f"  overlay would replace an existing file without replace:true -> {target}")
        bad = True
    elif exists:
        want = op.get("expectedSha256")
        have = hashlib.sha256(open(path, "rb").read()).hexdigest()
        if not want:
            print(f"  replace overlay missing expectedSha256 -> {target} (current {have})")
            bad = True
        elif want != have:
            print(f"  expectedSha256 stale for {target}")
            print(f"    manifest {want}")
            print(f"    base     {have}")
            bad = True
    elif op.get("replace"):
        print(f"  replace:true but target does not exist in the base -> {target}")
        bad = True
sys.exit(1 if bad else 0)
OVERLAYPY
  then red "  overlay checks FAILED"; fail=1; continue; fi
  overlays=$(python3 -c '
import json,sys
m=json.load(open(sys.argv[1]))
print(sum(1 for o in m.get("operations",[]) if o.get("type")=="overlay"))
' "$manifest")
  [[ "$overlays" -gt 0 ]] && green "  $overlays overlay target(s) ok"

  # patches must apply to the base
  patch_fail=0
  while IFS= read -r src; do
    [[ -z "$src" ]] && continue
    if git -C "$AMBXST_SRC" apply --check --whitespace=error-all "$pkg/$src" 2>/dev/null; then
      green "  patch applies: $src"
    else
      red   "  patch does NOT apply verbatim: $src"
      warn  "    the manager retries as a three-way merge, but regenerate it against $BASE_VERSION"
      patch_fail=1
    fi
  done < <(python3 -c '
import json,sys
m=json.load(open(sys.argv[1]))
for op in m.get("operations",[]):
    if op.get("type")=="patch" and op.get("source"): print(op["source"])
' "$manifest")
  [[ $patch_fail -eq 0 ]] || fail=1

  # a package may carry its own tests; run them if present
  if [[ -x "$pkg/tests/run.sh" ]]; then
    log="$(mktemp)"
    if (cd "$pkg" && AMBXST_SRC="$AMBXST_SRC" ./tests/run.sh >"$log" 2>&1); then
      green "  tests passed: $(grep -oE '[0-9]+ passed, [0-9]+ failed' "$log" | tail -1)"
    else
      red "  tests FAILED"; sed 's/^/    /' "$log" | tail -15; fail=1
    fi
    rm -f "$log"
  fi

  # testedBaseCommits honesty
  python3 - "$manifest" "$BASE_COMMIT" <<'PY'
import json, sys
m = json.load(open(sys.argv[1])); base = sys.argv[2]
tested = m.get("compatibility", {}).get("testedBaseCommits", [])
if base in tested:
    print(f"  testedBaseCommits lists this base")
else:
    print(f"  ! testedBaseCommits does not list {base}; add it once verified running")
PY
  echo
done

# Composition check. The manager applies every enabled package onto one tree, so
# patches that each apply alone can still collide with each other. Replay them
# in sequence against a scratch copy of the base.
if [[ ${#packages[@]} -gt 1 && $fail -eq 0 ]]; then
  blue "== composition (all packages onto one tree)"
  scratch="$(mktemp -d)"
  trap 'rm -rf "$scratch"' EXIT
  git -C "$AMBXST_SRC" archive HEAD | tar -x -C "$scratch"
  git -C "$scratch" init -q && git -C "$scratch" add -A >/dev/null 2>&1
  git -C "$scratch" -c user.email=v@l -c user.name=v commit -qm base >/dev/null 2>&1
  for pkg in "${packages[@]}"; do
    while IFS= read -r src; do
      [[ -z "$src" ]] && continue
      if git -C "$scratch" apply --whitespace=nowarn "$pkg/$src" 2>/dev/null; then
        green "  applied $(basename "$pkg")/$(basename "$src")"
      else
        red "  COLLISION applying $(basename "$pkg")/$(basename "$src") after earlier packages"
        fail=1
      fi
    done < <(python3 -c '
import json,sys
m=json.load(open(sys.argv[1]))
for op in m.get("operations",[]):
    if op.get("type")=="patch" and op.get("source"): print(op["source"])
' "$pkg/ambxst.mod.json")
  done
  echo
fi

# Cross-component property check on the composed tree. qmllint cannot resolve
# Quickshell's qs.* modules, so it never sees a mod assigning a property that the
# base component does not have. That failure only appears when the QML engine
# instantiates the tree, which inside the mod manager means failing the startup
# health window and rolling back.
if [[ $fail -eq 0 ]]; then
  blue "== cross-component properties"
  tree="$(mktemp -d)"
  if AMBXST_SRC="$AMBXST_SRC" "$repo_root/scripts/compose.sh" "$tree" "${packages[@]}" >/dev/null 2>&1; then
    if out=$(python3 "$repo_root/scripts/check-props.py" "$tree" "${packages[@]}" 2>&1); then
      green "  $(echo "$out" | tail -1)"
    else
      echo "$out" | grep -vE '^==' | sed 's/^/  /'
      red "  property checks FAILED"; fail=1
    fi
  else
    red "  could not compose the tree for property checks"; fail=1
  fi
  rm -rf "$tree"
  echo
fi

if [[ $fail -eq 0 ]]; then green "all packages passed against $BASE_VERSION"; else red "one or more packages failed"; fi
exit $fail
