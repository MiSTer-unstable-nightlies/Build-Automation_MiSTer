#!/usr/bin/env bash
set -euo pipefail

export GITHUB_TOKEN="${GITHUB_TOKEN}"
gh api orgs/:owner/repos > repos.json

gh release create "json" -p || true
gh release upload "json" "repos.json" --clobber
