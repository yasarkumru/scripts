#!/bin/bash
gem_file=$(sudo find /sys/kernel/debug/dri/ -name i915_gem_objects 2>/dev/null | head -1)
bytes=$(sudo cat "$gem_file" 2>/dev/null | awk 'NR==1 { print $(NF-1) }')
gb=$(echo "scale=2; $bytes / 1024 / 1024 / 1024" | bc)
echo "iGPU: ${gb} GB"

pids=$(fuser /dev/dri/renderD128 2>/dev/null)
if [ -n "$pids" ]; then
    echo ""
    echo "Loaded applications:"
    for pid in $pids; do
        cat "/proc/$pid/comm" 2>/dev/null
    done | sort -u | sed 's/^/  /'
fi
