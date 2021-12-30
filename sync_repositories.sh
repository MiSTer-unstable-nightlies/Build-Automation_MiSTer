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

    local LAST_BOT_COMMIT=$(git log --pretty=format:"%cn %H" | grep "Unstable Nightlies Bot" | head -n 1 | awk '{print $4}')
    local CHERRY_PICK_COMMIT=

    if [[ "${LAST_BOT_COMMIT_ID}" != "" ]] ; then
        CHERRY_PICK_COMMIT=$(git log --format=%B -n 1 ${LAST_BOT_COMMIT} 2> /dev/null | awk NF | tail -n 1 | awk '{print $5}' | sed 's/.$//')
    fi

    local PUSH="false"
    if [[ "${LAST_BOT_COMMIT_ID}" != "" ]] && [[ "${CHERRY_PICK_COMMIT}" != "" ]] ; then
        echo "LAST_BOT_COMMIT: ${LAST_BOT_COMMIT}"
        echo "CHERRY_PICK_COMMIT: ${CHERRY_PICK_COMMIT}"
        echo
        echo "Cherry Pick ${CHERRY_PICK_COMMIT}..upstream/${BRANCH}"
        if git cherry-pick -x ${CHERRY_PICK_COMMIT}..upstream/${BRANCH} ; then
            PUSH="true"
        fi
    else
        echo "Cherry Pick HEAD..upstream/${BRANCH}"
        if git cherry-pick -x HEAD..upstream/${BRANCH} ; then
            PUSH="true"
        fi
    fi

    if [[ "${PUSH}" == "true" ]] ; then
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
