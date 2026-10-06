#!/bin/sh
set -eu
physical=$(awk '/MemTotal:/ {printf "%.0f\n", $2 * 1024}' /proc/meminfo)
limit=$physical
for file in /sys/fs/cgroup/memory.max /sys/fs/cgroup/memory/memory.limit_in_bytes; do
    if [ -r "$file" ]; then
        value=$(cat "$file")
        case "$value" in max) ;; *) [ "$value" -lt "$limit" ] && limit=$value;; esac
        break
    fi
done
limit_mb=$((limit / 1024 / 1024))
if [ -n "${CIVICSIGNAL_PROCESS_MEMORY_MB:-}" ] && [ "$CIVICSIGNAL_PROCESS_MEMORY_MB" -lt "$limit_mb" ]; then
    limit_mb=$CIVICSIGNAL_PROCESS_MEMORY_MB
fi
echo "$limit_mb"
