# Overview

Docker Compose for aptos docker

Meant to be used with [central-proxy-docker](https://github.com/CryptoManufaktur-io/central-proxy-docker) for traefik
and Prometheus remote write; use `:ext-network.yml` in `COMPOSE_FILE` inside `.env` in that case.

If you want the RPC ports exposed locally, use `rpc-shared.yml` in `COMPOSE_FILE` inside `.env`.

## Quick Start

The `./aptosd` script can be used as a quick-start:

`./aptosd install` brings in docker-ce, if you don't have Docker installed already.

`cp default.env .env`

`nano .env` and adjust variables as needed.

`./aptosd up`

## Software update

To update the software, run `./aptosd update` and then `./aptosd up`

## Customization

`custom.yml` is not tracked by git and can be used to override anything in the provided yml files. If you use it,
add it to `COMPOSE_FILE` in `.env`

## Ledger pruning

The node config is rendered from `aptos/${NETWORK}/fullnode.yaml.sample` by
`aptos/docker-entrypoint.sh` on every container start, and written to `/opt/aptos/run/fullnode.yaml` inside
the container. There is no `fullnode.yaml` on the host to edit - change the sample, or set these in `.env`:

- `LEDGER_PRUNER_ENABLED` - default `false`
- `LEDGER_PRUNE_WINDOW` - default `360000000`, only takes effect when the pruner is enabled

Aptos enables the ledger pruner by default with a 90M window, so `LEDGER_PRUNER_ENABLED=false` is written into
the config explicitly. Omitting the keys entirely turns pruning *on*, not off.

`LEDGER_PRUNE_WINDOW` is a transaction count, not a duration, so how much history it buys depends on chain
throughput. At roughly 20M transactions/day on mainnet, 360M is about 18 days. Aptos warns below 50M and
subtracts a 200k `user_pruning_window_offset`, so the effective window is slightly smaller than configured.

Widening the window does not recover already-pruned history - the pruner simply idles until the node has
accumulated enough new history to reach the new window, and disk grows until then.

After changing either setting, restart the node. The entrypoint logs the values it applied, so
`./aptosd logs | grep docker-entrypoint` confirms what the node actually started with, and
`./aptosd cmd exec aptos cat /opt/aptos/run/fullnode.yaml` shows the rendered config.

Once the retention window is full, `oldest_ledger_version` from the `/v1` endpoint advances as old data is
pruned. Note it does *not* advance while the window is still filling - a node that previously ran a smaller
window will hold `oldest_ledger_version` steady until it has accumulated enough history to reach the new one,
which is the pruner working correctly rather than a fault.

Never cold-start a fresh Chainlink relayer against a pruned node - the LogPoller starts at offset 0 (genesis),
which is already pruned.

An earlier version of this repo rendered the config to `aptos/${NETWORK}/fullnode.yaml` on the host. That file
is no longer read and can be deleted; it stays gitignored so a leftover copy does not show up as untracked.

## Sync Check

Run:

`./aptosd check-sync`

Default `check-sync` settings:

- compose service: `aptos`
- local RPC: `http://127.0.0.1:${API_PORT:-8080}/v1`
- public RPC: `https://api.mainnet.aptoslabs.com/v1`
- lag threshold: `2` blocks

You can override defaults with:

`./scripts/check_sync.sh --compose-service aptos --local-rpc <url> --public-rpc <url> --block-lag <n> --env-file <path>`

## Version

aptos docker Docker uses a semver scheme.

This is aptos docker Docker v1.0.0
