#!/bin/bash

set -u
set -e

# Configure ZooKeeper
export ZOOCFGDIR=/opt/zookeeper/conf    # no slash at the end
export ZOOCFG=zoo.cfg
MC_ZOOKEEPER_DATA_DIR="${MC_ZOOKEEPER_DATA_DIR:-/var/lib/zookeeper}"
export ZOO_LOG_DIR="$MC_ZOOKEEPER_DATA_DIR"   # no slash at the end

export SERVER_JVMFLAGS="-Xms64m -Xmx256m"

# Custom logging configuration
export SERVER_JVMFLAGS="${SERVER_JVMFLAGS} -Dlog4j.configuration=file:///opt/zookeeper/conf/log4j.properties"


if [ ! -d /var/lib/zookeeper-template/ ]; then
    echo "ZooKeeper template data directory does not exist."
    exit 1
fi

mkdir -p "$MC_ZOOKEEPER_DATA_DIR"
# Seed only an empty directory. Existing coordination state survives restarts.
if [ -z "$(ls -A "$MC_ZOOKEEPER_DATA_DIR")" ]; then
    cp -R /var/lib/zookeeper-template/. "$MC_ZOOKEEPER_DATA_DIR/"
fi

exec /opt/zookeeper/bin/zkServer.sh start-foreground
