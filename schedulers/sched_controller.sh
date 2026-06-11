#!/bin/bash

DIR_REPO="$(dirname "$(readlink -f "$0")")"

cd "$DIR_REPO"

# --- VALIDACIÓN DE PRIVILEGIOS ---
# Ya que interactúa con eBPF y bpftool, el binario DEBE ejecutarse como root.
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: Este script requiere privilegios de root."
    echo "Ejecútalo con sudo o configura el bit SUID en el binario."
    exit 1
fi

# --- FUNCIÓN: setup.sh ---
setup_vmlinux() {
    echo "Generando el archivo vmlinux.h..."
    bpftool btf dump file /sys/kernel/btf/vmlinux format c > vmlinux.h
}

# --- FUNCIÓN: get_scx.sh ---
get_headers() {
    KERNEL_VERSION="v6.18"
    echo "Clonando headers mínimos de sched_ext ($KERNEL_VERSION)..."
    
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
        echo "Headers copiados a la carpeta scx/"
    else
        echo "Error al clonar el repositorio del kernel."
        return 1
    fi
}

# --- FUNCIÓN: build.sh ---
build_scheduler() {
    BPF_FILE=${1:-sched_ext.bpf.c}

    if [ ! -f vmlinux.h ]; then
        setup_vmlinux
    fi

    if [ ! -d "scx" ]; then
        echo "Headers 'scx' no encontrados."
        get_headers
    fi

    echo "Compilando el planificador: $BPF_FILE ..."
    clang-19 -target bpf -mcpu=v3 -g -O2 -c "$BPF_FILE" -o "${BPF_FILE}.o" -I.
}

# --- FUNCIÓN: stop.sh ---
stop_scheduler() {
    echo "Removiendo el planificador actual..."
    if [ -e /sys/fs/bpf/sched_ext/sched_ops ]; then
        rm /sys/fs/bpf/sched_ext/sched_ops
        echo "Planificador detenido con éxito."
    else
        echo "No hay ningún planificador activo en este momento."
    fi
}

# --- FUNCIÓN: start.sh ---
start_scheduler() {
    C_FILE=${1:-sched_ext.bpf.c}

    if [ "$C_FILE" = "--help" ]; then
        echo "Uso: scx-manager start [scheduler_file.c]"
        echo "Archivos de planificador disponibles en este directorio:"
        ls -1 *.bpf.c 2>/dev/null || echo "  (Ninguno encontrado)"
        exit 0
    fi

    # Llama internamente a las funciones unificadas
    build_scheduler "$C_FILE"
    stop_scheduler

    echo "Registrando el nuevo planificador..."
    bpftool struct_ops register "${C_FILE}.o" /sys/fs/bpf/sched_ext || { 
        echo "Error al registrar el planificador. Asegúrate de limpiar antes."
        exit 1
    }

    echo "Estado del planificador instalado:"
    cat /sys/kernel/sched_ext/root/ops || { 
        echo "No se pudo validar la instalación del planificador."
        exit 1
    }
}

# --- FUNCIÓN: scheduler.sh ---
status_scheduler() {
    if [ -f /sys/kernel/sched_ext/root/ops ]; then
        echo "Planificador personalizado en ejecución:"
        cat /sys/kernel/sched_ext/root/ops
    else
        echo "No hay ningún planificador sched_ext activo."
    fi
}

# --- ENRUTADOR PRINCIPAL ---
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
        echo "Gestor Unificado de Planificadores sched_ext (API Test)"
        echo "Uso: scx-manager {setup|get-headers|build|start|stop|status} [argumentos]"
        echo ""
        echo "Comandos:"
        echo "  setup         Genera el archivo vmlinux.h"
        echo "  get-headers   Descarga los headers mínimos del Kernel"
        echo "  build [file]  Compila un archivo .c a eBPF (Por defecto: sched_ext.bpf.c)"
        echo "  start [file]  Compila, detiene el anterior y registra el nuevo planificador"
        echo "  stop          Remueve el planificador de la API/sistema"
        echo "  status        Muestra el planificador que se está ejecutando"
        exit 1
        ;;
esac
