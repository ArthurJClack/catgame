#!/usr/bin/env bash
# cat game dedicated server (linux). edit the settings, then ./run_server.sh
# open udp PORT (cats) and QUERY_PORT (steam server list) in your firewall / router.
#
# steam server list: steam's game server library needs steamclient.so in ~/.steam/sdk64/. if you
# don't have the steam client on this box, get it with steamcmd (https://developer.valvesoftware.com/wiki/SteamCMD):
#   steamcmd +login anonymous +app_update 1007 +quit
#   mkdir -p ~/.steam/sdk64 && cp ~/Steam/steamapps/common/"Steamworks SDK Redist"/linux64/steamclient.so ~/.steam/sdk64/
# without it the server still runs, players just join by ip.
NAME="${NAME:-cat server}"
MAP="${MAP:-house}"            # house / forest / docks / trail / arena
PORT="${PORT:-24680}"
QUERY_PORT="${QUERY_PORT:-27016}"
MAX="${MAX:-16}"
MOTD="${MOTD:-}"
TOKEN="${CATGAME_GSLT:-}"      # optional steam game server login token: same server id every restart

cd "$(dirname "$0")"
while true; do
  ./CatGameServer.x86_64 --headless -- --server --name "$NAME" --map "$MAP" --port "$PORT" \
    --query-port "$QUERY_PORT" --max "$MAX" --motd "$MOTD" ${TOKEN:+--token "$TOKEN"}
  echo "server stopped ($?), restarting in 5 s (ctrl+c to quit)"
  sleep 5
done
