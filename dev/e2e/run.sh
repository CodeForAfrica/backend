#!/usr/bin/env bash
# Requires a separately initialized PostgreSQL fixture named civicsignal_e2e.
set -euo pipefail
cd "$(dirname "$0")/../.."
compose=(docker compose --env-file .env.e2e.local -f compose.yaml -f compose.e2e.yaml -p civicsignal-e2e)
"${compose[@]}" up -d --wait --wait-timeout 300
"${compose[@]}" cp dev/e2e/verify.py webapp-api:/tmp/civicsignal-e2e-verify.py
"${compose[@]}" exec -T webapp-api python3 /tmp/civicsignal-e2e-verify.py
"${compose[@]}" exec -T pipeline import_solr_data.pl --empty_queue
"${compose[@]}" exec -T webapp-api python3 /tmp/civicsignal-e2e-verify.py --search
