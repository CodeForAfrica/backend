#!/bin/bash
set -euo pipefail
mkdir -p /state/rss
chmod 0777 /state/rss
# Cron starts with a clean environment. Quote values instead of writing a DB
# password verbatim into /etc/environment (which cannot represent every URL).
{
    echo '#!/bin/bash'
    while IFS= read -r -d '' entry; do
        name=${entry%%=*}
        case "$name" in MC_*|PERL5LIB|PYTHONPATH|PERL_INLINE_DIRECTORY|PATH)
            printf 'export %s=%q\n' "$name" "${entry#*=}";;
        esac
    done < <(env -0)
} > /etc/civicsignal-environment.sh
chmod 0600 /etc/civicsignal-environment.sh
exec "$@"
