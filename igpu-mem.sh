#!/bin/bash
bytes=$(sudo awk 'NR==1 { print $(NF-1) }' /sys/kernel/debug/dri/1/i915_gem_objects 2>/dev/null)
gb=$(echo "scale=2; $bytes / 1024 / 1024 / 1024" | bc)
echo "iGPU: ${gb} GB"
