#!/bin/bash

DIR_REPO="$(dirname "$(readlink -f "$0")")"

cd "$DIR_REPO"

# --- PRIVILEGE VALIDATION ---
# Since it interacts with eBPF and bpftool, the binary MUST be executed as root.
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script requires root privileges."
    echo "Run it with sudo or configure the SUID bit on the binary."
    exit 1
fi

# --- FUNCTION: setup.sh ---
setup_vmlinux() {
    echo "Generating vmlinux.h file..."
    bpftool btf dump file /sys/kernel/btf/vmlinux format c > vmlinux.h
}

# --- FUNCTION: get_scx.sh ---
get_headers() {
    KERNEL_VERSION="v6.18"
    echo "Cloning minimal sched_ext headers ($KERNEL_VERSION)..."
    
    git clone --depth 1 \
      --branch "$KERNEL_VERSION" \
      --filter=blob:none \
      --sparse \
      https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git \
      kernel_src

    if [ -d "kernel_src" ]; then
        (
            cd kernel_src || exit
            git sparse-checkout set tools/sched_ext/include
        )
        mkdir -p scx
        cp -r kernel_src/tools/sched_ext/include/scx/* scx/
        rm -rf kernel_src
        echo "Headers copied to the scx/ folder"
    else
        echo "Error cloning the kernel repository."
        return 1
    fi
}

# --- FUNCTION: build.sh ---
build_scheduler() {
    BPF_FILE=${1:-sched_ext.bpf.c}

    if [ ! -f vmlinux.h ]; then
        setup_vmlinux
    fi

    if [ ! -d "scx" ]; then
        echo "'scx' headers not found."
        get_headers
    fi

    echo "Compiling the scheduler: $BPF_FILE ..."
    clang-19 -target bpf -mcpu=v3 -g -O2 -c "$BPF_FILE" -o "${BPF_FILE}.o" -I.
}

# --- FUNCTION: stop.sh ---
stop_scheduler() {
    echo "Removing the current scheduler..."
    if [ -e /sys/fs/bpf/sched_ext/sched_ops ]; then
        rm /sys/fs/bpf/sched_ext/sched_ops
        echo "Scheduler successfully stopped."
    else
        echo "There is no active scheduler at the moment."
    fi
}

# --- FUNCTION: start.sh ---
start_scheduler() {
    C_FILE=${1:-sched_ext.bpf.c}

    if [ "$C_FILE" = "--help" ]; then
        echo "Usage: scx-manager start [scheduler_file.c]"
        echo "Available scheduler files in this directory:"
        ls -1 *.bpf.c 2>/dev/null || echo "  (None found)"
        exit 0
    fi

    # Internally calls the unified functions
    build_scheduler "$C_FILE"
    stop_scheduler

    echo "Registering the new scheduler..."
    bpftool struct_ops register "${C_FILE}.o" /sys/fs/bpf/sched_ext || { 
        echo "Error registering the scheduler. Make sure to clean up beforehand."
        exit 1
    }

    echo "Installed scheduler status:"
    cat /sys/kernel/sched_ext/root/ops || { 
        echo "Could not validate scheduler installation."
        exit 1
    }
}

# --- FUNCTION: scheduler.sh ---
status_scheduler() {
    if [ -f /sys/kernel/sched_ext/root/ops ]; then
        echo "Custom scheduler currently running:"
        cat /sys/kernel/sched_ext/root/ops
    else
        echo "No active sched_ext scheduler found."
    fi
}

# --- MAIN ROUTER ---
case "$1" in
    setup)
        setup_vmlinux
        ;;
    get-headers)
        get_headers
        ;;
    build)
        build_scheduler "$2"
        ;;
    stop)
        stop_scheduler
        ;;
    start)
        start_scheduler "$2"
        ;;
    status)
        status_scheduler
        ;;
    *)
        echo "Unified sched_ext Scheduler Manager (API Test)"
        echo "Usage: scx-manager {setup|get-headers|build|start|stop|status} [arguments]"
        echo ""
        echo "Commands:"
        echo "  setup         Generates the vmlinux.h file"
        echo "  get-headers   Downloads minimal Kernel headers"
        echo "  build [file]  Compiles a .c file to eBPF (Default: sched_ext.bpf.c)"
        echo "  start [file]  Compiles, stops the previous one, and registers the new scheduler"
        echo "  stop          Removes the scheduler from the API/system"
        echo "  status        Shows the currently running scheduler"
        exit 1
        ;;
esac
