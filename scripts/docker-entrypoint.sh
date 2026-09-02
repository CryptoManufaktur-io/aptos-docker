#!/usr/bin/env bash
# Render the aptos-node config from its sample, applying the ledger pruner settings.
#
# Aptos enables the ledger pruner by default with a 90M transaction window, so "off" has to
# be written into the config explicitly - omitting the keys turns pruning on, it does not
# turn it off.
#
# This runs on every container start, so a change to .env takes effect on the next restart
# however the container is started. The rendered config is written inside the container
# rather than back into the bind-mounted config directory, so it cannot drift from the
# sample or be hand-edited on the host.
set -euo pipefail

__sample=/opt/aptos/etc/fullnode.yaml.sample
__config=/opt/aptos/run/fullnode.yaml

if [[ ! -f "${__sample}" ]]; then
  echo "docker-entrypoint: ${__sample} not found" >&2
  exit 1
fi

mkdir -p "$(dirname "${__config}")"
sed \
  -e "s/@LEDGER_PRUNER_ENABLED@/${LEDGER_PRUNER_ENABLED:-false}/" \
  -e "s/@LEDGER_PRUNE_WINDOW@/${LEDGER_PRUNE_WINDOW:-360000000}/" \
  "${__sample}" > "${__config}"

echo "docker-entrypoint: ledger pruner enable=${LEDGER_PRUNER_ENABLED:-false}" \
  "prune_window=${LEDGER_PRUNE_WINDOW:-360000000}"

# exec so aptos-node replaces this shell and keeps receiving tini's signals, which the
# stop_grace_period in aptos.yml depends on for a clean RocksDB shutdown
exec "$@"
