#!/bin/bash
# sched_scx_controller — para schedulers del repo sched-ext/scx

SCX_REPO="${SCX_REPO:-}"  # se puede sobreescribir con variable de entorno

# Parsear --repo=... de los argumentos
parse_repo_flag() {
    local args=()
    for arg in "$@"; do
        case "$arg" in
            --repo=*)
                SCX_REPO="${arg#*=}"
                ;;
            *)
                args+=("$arg")
                ;;
        esac
    done
    set -- "${args[@]}"
    echo "$@"
}

# Añadir al PATH si encontramos el repo
setup_scx_path() {
    if [ -n "$SCX_REPO" ]; then
        if [ -d "$SCX_REPO/target/release" ]; then
            export PATH="$SCX_REPO/target/release:$PATH"
            echo "Using scx repo: $SCX_REPO" >&2
        else
            echo "Warning: SCX_REPO=$SCX_REPO but target/release/ not found" >&2
        fi
    else
        # Autodiscovery en ubicaciones comunes
        for candidate in "$HOME/scx" "$HOME/repos/scx" "$HOME/src/scx" "/opt/scx"; do
            if [ -d "$candidate/target/release" ]; then
                export PATH="$candidate/target/release:$PATH"
                echo "Auto-detected scx repo: $candidate" >&2
                break
            fi
        done
    fi
}

stop_scheduler() {
    echo "Removing the current scx scheduler..."

    # Detectar qué scheduler está activo leyendo /sys
    ACTIVE=$(cat /sys/kernel/sched_ext/*/ops 2>/dev/null)

    if [ -z "$ACTIVE" ] || [ "$ACTIVE" = "ext" ]; then
        echo "There is no active scx scheduler at the moment."
        return 0
    fi

    # Buscar el PID del proceso que ejecuta ese scheduler
    PID=$(pgrep -f "scx_$ACTIVE" 2>/dev/null)

    if [ -n "$PID" ]; then
        sudo kill "$PID"
        wait "$PID" 2>/dev/null
        echo "Scheduler '$ACTIVE' (PID: $PID) successfully stopped."
    else
        # Fallback si el nombre no coincide exactamente
        echo "Warning: scheduler '$ACTIVE' detected but process not found."
        echo "Attempting broad cleanup..."
        sudo pkill -f "scx_" 2>/dev/null || true
    fi
}

start_scheduler() {
    SCHEDULER=${1:-scx_rusty}
    shift 2>/dev/null || true

    if [ "$SCHEDULER" = "--help" ] || [ "$SCHEDULER" = "-h" ]; then
        echo "Usage: scx-manager start <scheduler_name> [flags]"
        exit 0
    fi

    if ! command -v "$SCHEDULER" &>/dev/null; then
        echo "Error: '$SCHEDULER' not found in PATH."
        exit 1
    fi

    stop_scheduler  # limpia cualquier scheduler previo

    echo "Starting $SCHEDULER..."
    sudo "$SCHEDULER" "$@" &

    sleep 1
    ACTIVE=$(cat /sys/kernel/sched_ext/*/ops 2>/dev/null)
    if [ "$ACTIVE" != "$SCHEDULER" ]; then
        echo "Error: $SCHEDULER failed to activate."
        sudo pkill -f "$SCHEDULER" 2>/dev/null || true
        exit 1
    fi

    PID=$!
    echo "Scheduler '$SCHEDULER' active (PID: $PID)"
}

status_scheduler() {
    ACTIVE=$(cat /sys/kernel/sched_ext/*/ops 2>/dev/null)
    STATE=$(cat /sys/kernel/sched_ext/state 2>/dev/null)
    if [ -n "$ACTIVE" ]; then
        echo "sched_ext state: $STATE"
        echo "Active scheduler: $ACTIVE"
        if [ -e "$PIDFILE" ]; then
            echo "PID file: $(cat "$PIDFILE")"
        fi
    else
        echo "No active scx scheduler."
    fi
}

# 1. Extraer --repo de los argumentos
set -- "$(parse_repo_flag "$@")"

# 2. Configurar PATH
setup_scx_path

case "${1:-}" in
    start)  shift; start_scheduler "$@" ;;
    stop)   stop_scheduler ;;
    status) status_scheduler ;;
    restart) shift; stop_scheduler; start_scheduler "$@" ;;
    *)      echo "Usage: $0 {start|stop|status|restart} [scheduler] [flags]"
            echo ""
            echo "Examples:"
            echo "  $0 start scx_rusty --monitor 0.5"
            echo "  $0 start scx_lavd"
            echo "  $0 stop"
            echo "  $0 status"
            exit 1 ;;
esac
