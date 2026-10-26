#!/usr/bin/env bash
# Orchard ships desktop builds from its own depot, not GitHub releases:
# print the version advertised by the signed canary channel manifest.
set -euo pipefail
curl -fsSL https://depot.sfg545.dev/releases/canary.json | jq -r .payload | base64 -d | jq -r .version
