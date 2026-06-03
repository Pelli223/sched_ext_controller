#!/bin/bash
# extract_scx_headers.sh - Ahora con versión específica

# Define la versión de tu kernel (cambia si es distinta)
KERNEL_VERSION="v6.18"

# Clonar solo la versión específica del kernel
git clone --depth 1 \
  --branch "$KERNEL_VERSION" \
  --filter=blob:none \
  --sparse \
  https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git \
  kernel_src

cd kernel_src
git sparse-checkout set tools/sched_ext/include
cd ..

# Crear directorio destino (lo llamamos 'scx' como antes)
mkdir -p scx

# Copiar los headers
cp -r kernel_src/tools/sched_ext/include/scx/* scx/

# Limpiar
rm -rf kernel_src

echo "Headers de $KERNEL_VERSION copiados a scx/"
