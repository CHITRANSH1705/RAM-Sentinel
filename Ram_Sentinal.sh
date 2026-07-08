#!/bin/bash
#
# ram-sentinel.sh - Monitor free RAM on Linux and alert when it drops
# below a threshold. Logs to syslog + a logfile, captures the top
# memory-consuming processes at trigger time, debounces repeat alerts,
# and prevents multiple instances from running at once.
#
# Usage: ram-sentinel.sh [options]
#   -t THRESHOLD_MB   Alert when free RAM drops below this many MB (default: 500)
#   -i INTERVAL_SEC   Seconds between checks (default: 15)
#   -c COOLDOWN_SEC   Minimum seconds between repeat alerts (default: 300)
#   -l LOGFILE        Path to logfile (default: ~/.local/state/ram-sentinel/ram-sentinel.log)
#   -p PIDFILE        Path to pidfile (default: /tmp/ram-sentinel.pid)
#   -n                Disable desktop notifications (log-only mode; use over SSH)
#   -o                Run once and exit (no loop) - useful for cron
#   -h                Show this help and exit
#
# Exit codes: 0 ok, 1 bad args/deps, 2 already running

set -euo pipefail

# --------- Defaults (overridable by flags) ---------
THRESHOLD=500
CHECK_INTERVAL=15
COOLDOWN=300
NOTIFY=1
RUN_ONCE=0
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/ram-sentinel"
LOGFILE="$STATE_DIR/ram-sentinel.log"
PIDFILE="/tmp/ram-sentinel.pid"

usage() {
    cat <<'EOF'
ram-sentinel.sh - Monitor free RAM on Linux and alert when it drops
below a threshold. Logs to syslog + a logfile, captures the top
memory-consuming processes at trigger time, debounces repeat alerts,
and prevents multiple instances from running at once.

Usage: ram-sentinel.sh [options]
  -t THRESHOLD_MB   Alert when free RAM drops below this many MB (default: 500)
  -i INTERVAL_SEC   Seconds between checks (default: 15)
  -c COOLDOWN_SEC   Minimum seconds between repeat alerts (default: 300)
  -l LOGFILE        Path to logfile (default: ~/.local/state/ram-sentinel/ram-sentinel.log)
  -p PIDFILE        Path to pidfile (default: /tmp/ram-sentinel.pid)
  -n                Disable desktop notifications (log-only mode; use over SSH)
  -o                Run once and exit (no loop) - useful for cron
  -h                Show this help and exit

Exit codes: 0 ok, 1 bad args/deps, 2 already running
EOF
    exit "${1:-0}"
}

while getopts "t:i:c:l:p:noh" opt; do
    case "$opt" in
        t) THRESHOLD="$OPTARG" ;;
        i) CHECK_INTERVAL="$OPTARG" ;;
        c) COOLDOWN="$OPTARG" ;;
        l) LOGFILE="$OPTARG" ;;
        p) PIDFILE="$OPTARG" ;;
        n) NOTIFY=0 ;;
        o) RUN_ONCE=1 ;;
        h) usage 0 ;;
        *) usage 1 ;;
    esac
done

# --------- Validate numeric args ---------
for name in THRESHOLD CHECK_INTERVAL COOLDOWN; do
    val="${!name}"
    if ! [[ "$val" =~ ^[0-9]+$ ]]; then
        echo "Error: $name must be a non-negative integer, got '$val'" >&2
        exit 1
    fi
done

# --------- Dependency checks ---------
if ! command -v free >/dev/null 2>&1; then
    echo "Error: 'free' command not found (procps not installed?)" >&2
    exit 1
fi

if [ "$NOTIFY" -eq 1 ] && ! command -v notify-send >/dev/null 2>&1; then
    echo "Warning: notify-send not found - falling back to log-only mode." >&2
    echo "         (This is expected over SSH / headless sessions. Use -n to silence this.)" >&2
    NOTIFY=0
fi

HAVE_LOGGER=0
command -v logger >/dev/null 2>&1 && HAVE_LOGGER=1

mkdir -p "$(dirname "$LOGFILE")"

log() {
    local level="$1"; shift
    local msg="$*"
    local ts
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[$ts] [$level] $msg" >> "$LOGFILE"
    [ "$HAVE_LOGGER" -eq 1 ] && logger -t ram-sentinel "[$level] $msg"
}

# --------- Single-instance guard ---------
if [ -f "$PIDFILE" ]; then
    existing_pid="$(cat "$PIDFILE" 2>/dev/null || true)"
    if [ -n "$existing_pid" ] && kill -0 "$existing_pid" 2>/dev/null; then
        echo "Error: ram-sentinel already running (PID $existing_pid, pidfile $PIDFILE)" >&2
        exit 2
    fi
    log "WARN" "Stale pidfile found (PID $existing_pid not running); replacing it."
fi
echo $$ > "$PIDFILE"

cleanup() {
    log "INFO" "Shutting down (signal received)."
    rm -f "$PIDFILE"
    exit 0
}
trap cleanup INT TERM

log "INFO" "ram-sentinel started (threshold=${THRESHOLD}MB interval=${CHECK_INTERVAL}s cooldown=${COOLDOWN}s notify=${NOTIFY} pid=$$)"

last_alert_ts=0

check_once() {
    local free_ram
    free_ram=$(free -m | awk '/^Mem:/{print $7}')

    if [ -z "$free_ram" ]; then
        log "ERROR" "Could not read available RAM from 'free -m' output."
        return
    fi

    if [ "$free_ram" -lt "$THRESHOLD" ]; then
        local now
        now=$(date +%s)
        local since_last=$(( now - last_alert_ts ))

        if [ "$since_last" -ge "$COOLDOWN" ]; then
            log "ALERT" "Low RAM: ${free_ram}MB available (threshold ${THRESHOLD}MB)"

            # Capture top memory consumers for diagnosis - a runaway
            # process or a memory-exhaustion condition both show up here.
            local top_procs
            top_procs=$(ps -eo pid,pmem,pcpu,comm --sort=-pmem 2>/dev/null | head -6)
            log "INFO" "Top memory consumers (top 5 by %MEM):"
            printf '%s\n' "$top_procs" >> "$LOGFILE"

            if [ "$NOTIFY" -eq 1 ]; then
                notify-send "Low RAM Alert" "Available RAM is below ${THRESHOLD}MB (currently ${free_ram}MB)" 2>/dev/null || \
                    log "WARN" "notify-send call failed."
            fi

            last_alert_ts=$now
        else
            log "DEBUG" "Still low (${free_ram}MB) but within cooldown (${since_last}s/${COOLDOWN}s) - suppressing repeat alert."
        fi
    fi
}

if [ "$RUN_ONCE" -eq 1 ]; then
    check_once
    rm -f "$PIDFILE"
    exit 0
fi

while true; do
    check_once
    sleep "$CHECK_INTERVAL"
done
