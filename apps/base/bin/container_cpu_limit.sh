#!/bin/sh
set -eu
physical=$(nproc)
quota=-1
period=100000
if [ -r /sys/fs/cgroup/cpu.max ]; then
    read -r quota period < /sys/fs/cgroup/cpu.max
elif [ -r /sys/fs/cgroup/cpu/cpu.cfs_quota_us ]; then
    quota=$(cat /sys/fs/cgroup/cpu/cpu.cfs_quota_us)
    period=$(cat /sys/fs/cgroup/cpu/cpu.cfs_period_us)
fi
case "$quota" in max|-1) count=$physical;; *) count=$(((quota + period - 1) / period));; esac
if [ -n "${CIVICSIGNAL_PROCESS_CPU_COUNT:-}" ] && [ "$CIVICSIGNAL_PROCESS_CPU_COUNT" -lt "$count" ]; then
    count=$CIVICSIGNAL_PROCESS_CPU_COUNT
fi
echo "$count"
