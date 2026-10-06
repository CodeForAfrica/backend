#!/bin/sh
set -eu
upstream=${MC_WEBAPP_API_UPSTREAM:-webapp-api:9090}
# Keep replacement safe and reject config injection.
case "$upstream" in *[!a-zA-Z0-9.:-]*|'') echo 'Invalid API upstream' >&2; exit 1;; esac
sed "s/webapp-api:9090/$upstream/" /etc/nginx/include/webapp-httpd.conf.template > /etc/nginx/include/webapp-httpd.conf
mkdir -p /state/rss
exec "$@"
