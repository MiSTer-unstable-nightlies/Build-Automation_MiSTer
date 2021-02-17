#!/usr/bin/env bash
set -euo pipefail

export GITHUB_TOKEN="${GITHUB_TOKEN}"
gh api orgs/:owner/repos
