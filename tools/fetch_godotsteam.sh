#!/usr/bin/env bash
# Downloads the GodotSteam GDExtension into addons/godotsteam (steam lobbies + p2p for multiplayer).
# CI runs this before every export. Run it yourself (git bash / linux / mac) if you want steam
# while playing from the editor; without it the game still runs, multiplayer just says steam
# isn't in this build.
#
# GodotSteam lives on codeberg now (https://codeberg.org/godotsteam/godotsteam). This picks the
# newest GDExtension release whose compatibility_minimum still allows our Godot version.
# Override with GODOTSTEAM_URL=<zip url> to pin one.
set -euo pipefail

GODOT_VERSION="${GODOT_VERSION:-4.3}"
API="https://codeberg.org/api/v1/repos/godotsteam/godotsteam/releases?limit=40"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/addons/godotsteam"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

ver_le() { [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1)" = "$1" ]; }

try_zip() {
  local url="$1"
  echo "trying $url"
  rm -rf "$TMP/x" && mkdir -p "$TMP/x"
  curl -fsSL --retry 3 -o "$TMP/gs.zip" "$url" || return 1
  unzip -q -o "$TMP/gs.zip" -d "$TMP/x" || return 1
  local ext
  ext="$(find "$TMP/x" -name 'godotsteam.gdextension' | head -n1)"
  [ -n "$ext" ] || { echo "  no godotsteam.gdextension in it"; return 1; }
  local min
  min="$(grep -E '^compatibility_minimum' "$ext" | head -n1 | sed -E 's/[^0-9.]//g')"
  echo "  compatibility_minimum=${min:-?}"
  if [ -n "$min" ] && ! ver_le "$min" "$GODOT_VERSION"; then
    echo "  needs godot $min, we have $GODOT_VERSION, skipping"
    return 1
  fi
  local src
  src="$(dirname "$ext")"
  rm -rf "$DEST" && mkdir -p "$(dirname "$DEST")"
  cp -r "$src" "$DEST"
  echo "installed GodotSteam from $url into addons/godotsteam"
  ls -la "$DEST" | head -20
  return 0
}

if [ -n "${GODOTSTEAM_URL:-}" ]; then
  try_zip "$GODOTSTEAM_URL" && exit 0
  echo "GODOTSTEAM_URL didn't work"; exit 1
fi

curl -fsSL --retry 3 "$API" -o "$TMP/releases.json"
python3 - "$TMP/releases.json" > "$TMP/urls.txt" <<'PY'
import json, sys
rel = json.load(open(sys.argv[1]))
for r in rel:
    for a in r.get("assets", []):
        n = a["name"].lower()
        if n.endswith(".zip") and ("gdextension" in n or "gde" in n) and "server" not in n and "example" not in n:
            print(a["browser_download_url"], "#", r["tag_name"], a["name"], file=sys.stdout)
PY
echo "candidates:"; cat "$TMP/urls.txt"
while read -r url _rest; do
  [ -n "$url" ] || continue
  try_zip "$url" && exit 0
done < "$TMP/urls.txt"
echo "no GodotSteam GDExtension release works with godot $GODOT_VERSION"
exit 1
