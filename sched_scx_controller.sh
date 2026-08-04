#!/bin/bash

# Detectar home real incluso con sudo
if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
    REAL_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
else
    REAL_HOME="$HOME"
fi

# --- Parsear --repo=... ---
args=()
for arg in "$@"; do
    if [[ "$arg" == --repo=* ]]; then
        SCX_REPO="${arg#*=}"
    else
        args+=("$arg")
    fi
done
set -- "${args[@]}"

# --- Autodiscovery ---
if [ -z "$SCX_REPO" ]; then
    for candidate in "$REAL_HOME/scx" "$REAL_HOME/repos/scx" "$REAL_HOME/src/scx" "/opt/scx"; do
        if [ -d "$candidate/target/release" ]; then
            SCX_REPO="$candidate"
            echo "Auto-detected scx repo: $SCX_REPO" >&2
            break
        fi
    done
fi

if [ -z "$SCX_REPO" ] || [ ! -d "$SCX_REPO/target/release" ]; then
    echo "Error: scx repo not found. Use --repo=/path/to/scx" >&2
    exit 1
fi

# --- Funciones ---

stop_scheduler() {
    echo "Removing the current scx scheduler..."
    local ACTIVE=$(cat /sys/kernel/sched_ext/*/ops 2>/dev/null | head -n1)

    if [ -z "$ACTIVE" ] || [ "$ACTIVE" = "ext" ]; then
        echo "There is no active scx scheduler at the moment."
        return 0
    fi

    local PID=$(pgrep -xf "$SCX_REPO/target/release/scx_$ACTIVE" 2>/dev/null \
             || pgrep -f "scx_$ACTIVE" 2>/dev/null \
             || pgrep -f "$ACTIVE" 2>/dev/null)

    if [ -n "$PID" ]; then
        sudo kill "$PID"
        wait "$PID" 2>/dev/null
        echo "Scheduler '$ACTIVE' (PID: $PID) successfully stopped."
    else
        echo "Warning: scheduler '$ACTIVE' detected but process not found. Cleaning up..."
        sudo pkill -f "scx_" 2>/dev/null || true
    fi
}

start_scheduler() {
    local SCHEDULER="${1:-scx_rusty}"
    shift 2>/dev/null || true

    local SCHEDULER_BIN="$SCX_REPO/target/release/$SCHEDULER"
    if [ ! -x "$SCHEDULER_BIN" ]; then
        echo "Error: '$SCHEDULER' not found at $SCHEDULER_BIN"
        exit 1
    fi

    stop_scheduler

    echo "Starting $SCHEDULER..."
    sudo "$SCHEDULER_BIN" "$@" &
    local PID=$!

    sleep 1

    # Verificación robusta: el proceso sigue vivo Y sched_ext está activo
    if ! kill -0 "$PID" 2>/dev/null; then
        echo "Error: $SCHEDULER process died immediately."
        exit 1
    fi

    local STATE=$(cat /sys/kernel/sched_ext/state 2>/dev/null)
    local ACTIVE=$(cat /sys/kernel/sched_ext/*/ops 2>/dev/null | head -n1 | tr -d '\n')

    if [ "$STATE" != "enabled" ] || [ -z "$ACTIVE" ] || [ "$ACTIVE" = "ext" ]; then
        echo "Error: $SCHEDULER failed to activate."
        echo "  sched_ext state: ${STATE:-<empty>}"
        echo "  active ops: ${ACTIVE:-<empty>}"
        sudo kill "$PID" 2>/dev/null
        wait "$PID" 2>/dev/null
        exit 1
    fi

    echo "Scheduler '$SCHEDULER' active (PID: $PID, ops: $ACTIVE)"
}

status_scheduler() {
    local STATE=$(cat /sys/kernel/sched_ext/state 2>/dev/null)
    local ACTIVE=$(cat /sys/kernel/sched_ext/*/ops 2>/dev/null | head -n1)
    if [ -n "$ACTIVE" ] && [ "$ACTIVE" != "ext" ]; then
        echo "sched_ext state: $STATE"
        echo "Active scheduler: $ACTIVE"
    else
        echo "No active scx scheduler."
    fi
}

# --- Main ---
case "${1:-}" in
    start)
        shift
        start_scheduler "$@"
        ;;
    stop)
        stop_scheduler
        ;;
    status)
        status_scheduler
        ;;
    restart)
        shift
        stop_scheduler
        start_scheduler "$@"
        ;;
    *)
        echo "Usage: $0 [--repo=PATH] {start|stop|status|restart} [scheduler] [flags]"
        echo ""
        echo "Examples:"
        echo "  $0 start scx_rusty --monitor 0.5"
        echo "  $0 start scx_rustland"
        echo "  $0 --repo=/home/user/custom/scx start scx_lavd"
        echo "  $0 stop"
        exit 1
        ;;
esac
