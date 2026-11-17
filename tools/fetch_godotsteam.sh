#!/usr/bin/env bash
# Downloads the GodotSteam GDExtension into addons/godotsteam (steam lobbies + p2p for multiplayer).
# CI runs this before every export. Run it yourself (git bash / linux / mac) if you want steam
# while playing from the editor; without it the game still runs, multiplayer just says steam
# isn't in this build.
#
# GodotSteam lives on codeberg now (https://codeberg.org/godotsteam/godotsteam). This picks the
# newest GDExtension release whose compatibility_minimum still allows our Godot version.
# Override with GODOTSTEAM_URL=<zip url> to pin one.
#
# GODOTSTEAM_FLAVOR=server fetches GodotSteam *Server* instead (the SteamGameServer api, for the
# dedicated server builds) into addons/godotsteam_server. it's a separate extension; the client
# and server builds each carry one of the two, never both.
set -euo pipefail

export GODOT_VERSION="${GODOT_VERSION:-4.3}"
export FLAVOR="${GODOTSTEAM_FLAVOR:-client}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ "$FLAVOR" = "server" ]; then
  DEST="$ROOT/addons/godotsteam_server"
  REPOS="godotsteam/godotsteam godotsteam/godotsteam-server godotsteam/godotsteam_server"
else
  DEST="$ROOT/addons/godotsteam"
  REPOS="godotsteam/godotsteam"
fi
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
  if [ "$FLAVOR" = "server" ]; then
    ext="$(find "$TMP/x" -name '*.gdextension' | grep -i server | head -n1)"
  else
    ext="$(find "$TMP/x" -name 'godotsteam.gdextension' | head -n1)"
  fi
  [ -n "$ext" ] || { echo "  no ${FLAVOR} .gdextension in it"; find "$TMP/x" -name '*.gdextension'; return 1; }
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
  echo "installed GodotSteam ($FLAVOR) from $url into ${DEST#$ROOT/}"
  ls -la "$DEST" | head -20
  return 0
}

if [ -n "${GODOTSTEAM_URL:-}" ]; then
  try_zip "$GODOTSTEAM_URL" && exit 0
  echo "GODOTSTEAM_URL didn't work"; exit 1
fi

# newest first; the godot 4.3 builds are a few pages back
n=0
for repo in $REPOS; do
  for page in 1 2 3 4 5; do
    n=$((n+1))
    curl -fsSL --retry 3 "https://codeberg.org/api/v1/repos/$repo/releases?limit=50&page=$page" -o "$TMP/releases_$n.json" || break
  done
done
ls "$TMP"/releases_*.json >/dev/null 2>&1 || { echo "couldn't reach codeberg"; exit 1; }
python3 - "$TMP"/releases_*.json > "$TMP/urls.txt" <<'PY'
import json, os, re, sys
want = tuple(int(x) for x in os.environ.get("GODOT_VERSION", "4.3").split(".")[:2])
server = os.environ.get("FLAVOR") == "server"
rel = []
for f in sorted(sys.argv[1:], key=lambda x: int(x.rsplit("_", 1)[1].split(".")[0])):
    try:
        rel += json.load(open(f))
    except Exception:
        pass
for r in rel:
    for a in r.get("assets", []):
        n = a["name"].lower()
        if n.endswith(".zip") and ("gdextension" in n or "gde" in n) and (("server" in n) == server) and "example" not in n:
            # "plugin-4.4" or "plugin-44": built for that godot (godot-cpp), even when the
            # .gdextension's compatibility_minimum says older is fine. those crash on 4.3
            m = re.search(r"plugin-(\d)\.?(\d+)", n)
            if m and (int(m.group(1)), int(m.group(2))) > want:
                continue   # built for a newer godot, says so in the name
            print(a["browser_download_url"], "#", r["tag_name"], a["name"], file=sys.stdout)
PY
echo "candidates:"; cat "$TMP/urls.txt"
while read -r url _rest; do
  [ -n "$url" ] || continue
  try_zip "$url" && exit 0
done < "$TMP/urls.txt"
echo "no GodotSteam ($FLAVOR) GDExtension release works with godot $GODOT_VERSION"
exit 1
