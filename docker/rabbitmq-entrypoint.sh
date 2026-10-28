#!/bin/sh
set -eu
: "${MC_RABBITMQ_PASSWORD:?Set MC_RABBITMQ_PASSWORD}"
mkdir -p "$HOME" "$RABBITMQ_MNESIA_BASE"
export RABBITMQ_DEFAULT_USER=mediacloud
export RABBITMQ_DEFAULT_PASS="$MC_RABBITMQ_PASSWORD"
export RABBITMQ_DEFAULT_VHOST=/mediacloud
exec /usr/local/bin/docker-entrypoint.sh "$@"
