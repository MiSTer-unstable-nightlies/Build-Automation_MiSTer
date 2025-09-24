#!/usr/bin/env bash
set -euo pipefail

SYNC_DIR_TMP="$(mktemp -d)"
ERROR=0

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
    
    UPSTREAM_MESSAGE=$(git log --format=%B -n 1 upstream/${BRANCH})
    UPSTREAM_MESSAGE="${UPSTREAM_MESSAGE//\(#[0-9]*\)/}"
    UPSTREAM_MESSAGE="${UPSTREAM_MESSAGE//\(MiSTer-devel#[0-9]*\)/}"
    UPSTREAM_EMAIL=$(git log --format=%ae -n 1 upstream/${BRANCH})
    UPSTREAM_NAME=$(git log --format=%an -n 1 upstream/${BRANCH})
    UPSTREAM_SHA=$(git log --format=%H -n 1 upstream/${BRANCH})

    echo "Merging upstream/${BRANCH}..."
    if ! git merge --no-commit upstream/${BRANCH} ; then
        echo "WARNING: Merge failed!"
    fi
    if ! git commit -m "${UPSTREAM_MESSAGE}" --author "${UPSTREAM_NAME} <${UPSTREAM_EMAIL}>" ; then
        echo "WARNING: Commit failed!"
    fi

    local BEHIND AHEAD
    read BEHIND AHEAD < <(git rev-list --left-right --count "origin/${BRANCH}...HEAD")

    if [[ $AHEAD -gt 0 && $BEHIND -eq 0 ]]; then
        echo "Pushing!"
        echo git push "https://...:...@github.com/${USER}/${CORE_NAME}.git" origin "${BRANCH}"
        git push "https://${DISPATCH_USER}:${DISPATCH_TOKEN}@github.com/${USER}/${CORE_NAME}.git" "${BRANCH}"
    elif [[ $BEHIND -gt 0 && $AHEAD -eq 0 ]]; then
        echo "ERROR: We are behind! Try again later."
        ERROR=1
    elif [[ $BEHIND -gt 0 && $AHEAD -gt 0 ]]; then
        echo "ERROR: Branches diverged!"
        ERROR=1
    else
        echo "No need to push."
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
exit ${ERROR}
