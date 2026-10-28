#!/bin/bash
set -euo pipefail
source /etc/civicsignal-environment.sh
if [ "${1:-}" = sudo ]; then
    shift
    exec sudo -E "$@"
fi
exec "$@"
