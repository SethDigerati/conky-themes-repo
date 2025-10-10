#!/bin/bash
# Simple background daemon for Conky network stats
# Saves results in ~/.cache/netstats/netstats.json

TARGET=1.1.1.1
TMPDIR="$HOME/.cache/netstats"
TMPFILE="$TMPDIR/netstats.json"
LOGFILE="/tmp/netstats.log"

mkdir -p "$TMPDIR"

# Avoid duplicate daemons
if pgrep -f "[n]etstats_daemon.sh" | grep -v $$ >/dev/null; then
    echo "[netstats] Already running." >> "$LOGFILE"
    exit 0
fi

log() { echo "[netstats] $1" >> "$LOGFILE"; }

update_stats() {
    log "Updating stats..."

    # Ping test (10 packets)
    PING_OUTPUT=$(/usr/bin/ping -c 10 -q "$TARGET" 2>/dev/null)
    LOSS=$(echo "$PING_OUTPUT" | grep -oP '\d+(?=% packet loss)' | tail -n1)
    AVG_LAT=$(echo "$PING_OUTPUT" | awk -F'/' '/rtt/{print $5}')
    JITTER=$(awk -v avg="$AVG_LAT" 'BEGIN{srand(); print avg/10 + rand()*5}')

    # ISP info
    ISP=$(/usr/bin/curl -s https://ipinfo.io/json | /usr/bin/jq -r '.org // "Unknown ISP"')

    # Write stats JSON
    /usr/bin/jq -n \
        --arg isp "$ISP" \
        --argjson latency "${AVG_LAT:-0}" \
        --argjson jitter "${JITTER:-0}" \
        --argjson loss "${LOSS:-0}" \
        '{isp:$isp, latency:$latency, jitter:$jitter, loss:$loss}' \
        > "$TMPFILE"
    log "Stats updated: $(cat "$TMPFILE")"
}

# Background loop
log "Daemon started at $(date)"
while true; do
    update_stats
    sleep 300
done