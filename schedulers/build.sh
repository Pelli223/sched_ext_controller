#!/bin/sh

# Usage: ./build.sh bpf_file.c (default is sched_ext.bpf.c)

# Set the default file
BPF_FILE=${1:-sched_ext.bpf.c}

# Create the vmlinux header with all the eBPF Linux functions
# if it doesn'r exist
if [ ! -f vmlinux.h ]; then
  echo "Creating vmlinux.h"
  bpftool btf dump file /sys/kernel/btf/vmlinux format c >vmlinux.h
fi

# Check if scx headers exist, if not, download them
if [ ! -d "scx" ]; then
  echo "scx headers not found. Downloading minimal scx headers..."
  ./get_scx.sh
fi

# Compile the scheduler
clang-19 -target bpf -mcpu=v3 -g -O2 -c $BPF_FILE -o ${BPF_FILE}.o -I.
