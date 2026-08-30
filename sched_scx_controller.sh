#!/bin/bash

DIR_REPO="$(dirname "$(readlink -f "$0")")"

cd "$DIR_REPO"

# Detectar home real incluso con sudo
if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
    REAL_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
else
    REAL_HOME="$HOME"
fi

# --- PRIVILEGE VALIDATION ---
# Since it interacts with eBPF and bpftool, the binary MUST be executed as root.
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script requires root privileges."
    echo "Run it with sudo or configure the SUID bit on the binary."
    exit 1
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
    local ACTIVE=$(cat /sys/kernel/sched_ext/*/ops 2>/dev/null | head -n1 | tr -d '\n')

    if [ -z "$ACTIVE" ] || [ "$ACTIVE" = "ext" ]; then
        echo "There is no active scx scheduler at the moment."
        return 0
    fi

    # Extraer nombre base: rusty_1.1.2... → rusty
    local BASE_NAME="${ACTIVE%%_*}"
    local PID=""

    # Intentar varias estrategias de búsqueda
    if [ -n "$SCX_REPO" ]; then
        # 1. Buscar ejecutable exacto en el repo
        PID=$(pgrep -xf "$SCX_REPO/target/release/scx_$BASE_NAME" 2>/dev/null)
    fi

    if [ -z "$PID" ]; then
        # 2. Buscar por nombre de proceso scx_<base>
        PID=$(pgrep -f "scx_$BASE_NAME" 2>/dev/null)
    fi

    if [ -z "$PID" ]; then
        # 3. Buscar por cualquier cosa que contenga el nombre base
        PID=$(pgrep -f "$BASE_NAME" 2>/dev/null)
    fi

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
    shift 2>/dev/null || true # Elimina el $1 (nombre del scheduler) para dejar solo los argumentos extras en $@

    local SCHEDULER_BIN="$SCX_REPO/target/release/$SCHEDULER"
    if [ ! -x "$SCHEDULER_BIN" ]; then
        echo "Error: '$SCHEDULER' not found at $SCHEDULER_BIN"
        exit 1
    fi

    stop_scheduler

    if [ $# -gt 0 ]; then
        echo "Starting $SCHEDULER with arguments: $*..."
    else
        echo "Starting $SCHEDULER..."
    fi

    # Lanza el binario pasándole TODOS los argumentos restantes ("$@")
    sudo "$SCHEDULER_BIN" "$@" &
    local PID=$!

    # Polling: Esperar hasta 5 segundos a que se active el scheduler en eBPF
    local TIMEOUT=5
    local COUNT=0
    local STATE=""
    local ACTIVE=""

    while [ $COUNT -lt $TIMEOUT ]; do
        sleep 1
        
        # Verificar si el proceso murió prematuramente
        if ! kill -0 "$PID" 2>/dev/null; then
            echo "Error: $SCHEDULER process died immediately."
            exit 1
        fi

        STATE=$(cat /sys/kernel/sched_ext/state 2>/dev/null)
        ACTIVE=$(cat /sys/kernel/sched_ext/*/ops 2>/dev/null | head -n1 | tr -d '\n')

        # Si el kernel confirmó la activación, salimos del bucle con éxito
        if [ "$STATE" = "enabled" ] && [ -n "$ACTIVE" ] && [ "$ACTIVE" != "ext" ]; then
            echo "Scheduler '$SCHEDULER' active (PID: $PID, ops: $ACTIVE)"
            return 0
        fi

        COUNT=$((COUNT + 1))
    done

    # Si pasaron los 5 segundos sin activarse:
    echo "Error: $SCHEDULER failed to activate after ${TIMEOUT}s."
    echo "  sched_ext state: ${STATE:-<empty>}"
    echo "  active ops: ${ACTIVE:-<empty>}"
    sudo kill -SIGINT "$PID" 2>/dev/null
    wait "$PID" 2>/dev/null
    exit 1
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
