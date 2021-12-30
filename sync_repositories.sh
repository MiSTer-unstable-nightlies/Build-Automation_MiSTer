#!/usr/bin/env bash
set -euo pipefail

SYNC_DIR_TMP="$(mktemp -d)"

sync_repository() {
    local ORIGIN="${1}"
    local UPSTREAM="${2}"
    local BRANCH="${3}"
    local CORE_NAME="${4}"
    local USER="${5}"
    
    git clone "${ORIGIN}" "${SYNC_DIR_TMP}"
    pushd "${SYNC_DIR_TMP}" > /dev/null
    git remote add upstream "${UPSTREAM}"
    git fetch upstream
    if git cherry-pick -x HEAD.."upstream/${BRANCH}" ; then
        echo "Pushing!"
        echo git push "https://...:...@github.com/${USER}/${CORE_NAME}.git" origin "${BRANCH}"
        git push "https://${DISPATCH_USER}:${DISPATCH_TOKEN}@github.com/${USER}/${CORE_NAME}.git" "${BRANCH}"
    fi
    popd > /dev/null
    rm -rf "${SYNC_DIR_TMP}"
}

export GITHUB_TOKEN="${GITHUB_TOKEN}"
git config --global user.email "theypsilon@gmail.com"
git config --global user.name "Unstable Nightlies Bot"
gh api orgs/:owner/repos --paginate > repos.json

gh release create "json" -p || true
#gh release upload "json" "repos.json" --clobber

for name in $(cat repos.json | jq -r '.[] | .name') ; do
    echo
    echo "Core: ${name}"
    gh api repos/:owner/${name} > core.json
    #gh release upload "json" "core.json" --clobber

    ORIGIN_URL="$(cat core.json | jq -r '.clone_url')"
    UPSTREAM_URL="$(cat core.json | jq -r '.parent.clone_url')"
    DEFAULT_BRANCH="$(cat core.json | jq -r '.default_branch')"
    OWNER="$(cat core.json | jq -r '.owner.login')"

    echo "ORIGIN_URL: ${ORIGIN_URL}"
    echo "UPSTREAM_URL: ${UPSTREAM_URL}"
    echo "DEFAULT_BRANCH: ${DEFAULT_BRANCH}"
    echo "OWNER: ${OWNER}"
    echo

    if [[ "${UPSTREAM_URL}" == "null" ]] ; then
        echo "Skipped."
        continue
    fi

    sync_repository "${ORIGIN_URL}" "${UPSTREAM_URL}" "${DEFAULT_BRANCH}" "${name}" "${OWNER}"
done

echo "Done."
