#!/usr/bin/env bash
# Behavioural tests for this package's pure parsers, run from the package root.
#
# modules/services/nordvpn-parse.js and nordvpn-iso.js are .pragma library files
# with no QML imports, no Config and no side effects, so they load in plain node.
# No Quickshell, no compositor and no NordVPN subscription required.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
command -v node >/dev/null 2>&1 || { echo "node required"; exit 2; }

# The harness expects the parsers at modules/services and fixtures at
# lab/fixtures/nordvpn, so stage a throwaway tree with the payload copies.
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/modules/services" "$work/lab/fixtures/nordvpn"
cp payload/services/nordvpn-parse.js payload/services/nordvpn-iso.js "$work/modules/services/"
cp tests/fixtures/nordvpn/* "$work/lab/fixtures/nordvpn/"
cp tests/test-nordvpn-parse.sh "$work/lab/"
cd "$work" && bash lab/test-nordvpn-parse.sh "${1:-}"
