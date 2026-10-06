#!/bin/bash
set -euo pipefail
mkdir -p /state/solr
if [ ! -f /state/solr/start.jar ]; then
    cp -a /solr-template/. /state/solr/
fi
# Always use current schema; index data stays in the persistent directory.
cp -a /usr/src/solr/. /state/solr/
exec "$@"
