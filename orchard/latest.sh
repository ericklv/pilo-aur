#!/usr/bin/env bash
# The repo also publishes Android ("-mobile") and old prerelease tags, so
# releases/latest isn't reliable: take the newest stable desktop release.
set -euo pipefail
gh api 'repos/SFG5453/Orchard/releases?per_page=50' \
  --jq '[.[] | select(.draft | not) | select(.prerelease | not) | select(.tag_name | test("mobile") | not)][0].tag_name'
