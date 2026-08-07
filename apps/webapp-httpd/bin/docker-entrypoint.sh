#!/bin/sh

set -eu

# "webapp-api:9090" is the container's name from docker-compose.yml; override
# with "localhost:9090" when webapp-httpd and webapp-api are grouped in the
# same task (e.g. on AWS) instead of running as separate containers.
: "${MC_WEBAPP_API_UPSTREAM:=webapp-api:9090}"

# This base image doesn't have envsubst, so a plain sed substitution stands
# in for it. Delimited with "#" (not "/") since the replacement is a
# host[:port] value that could plausibly contain a slash.
sed "s#__MC_WEBAPP_API_UPSTREAM__#${MC_WEBAPP_API_UPSTREAM}#" \
    /etc/nginx/include/webapp-httpd.conf.template \
    > /etc/nginx/include/webapp-httpd.conf

exec nginx
