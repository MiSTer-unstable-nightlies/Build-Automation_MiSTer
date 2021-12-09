#!/usr/bin/env bash
set -euo pipefail

echo "Arguments"
echo "RELEASE_FILE_URL: ${RELEASE_FILE_URL}"
echo "CORE_NAME: ${CORE_NAME}"
echo "REPOSITORY: ${REPOSITORY}"
echo "RELEASE_TAG: ${RELEASE_TAG}"
echo "COMMIT_SHA: ${COMMIT_SHA}"
echo "COMMIT_MESSAGE: ${COMMIT_MESSAGE}"

if [[ "${WEBHOOK_URL:-}" != "" ]] ; then
    DISCORD_MESSAGE="Latest **${CORE_NAME}** unstable build: ${RELEASE_FILE_URL}"
    DISCORD_MESSAGE+="\n"
    DISCORD_MESSAGE+="\`\`\`Commit ${COMMIT_MESSAGE}\`\`\`"

    echo
    echo "Discord message:"
    echo "${DISCORD_MESSAGE}"
    echo

    curl \
        --fail \
        --output /dev/null \
        -i \
        -H "Accept: application/json" \
        -H "Content-Type:application/json" \
        -X POST \
        --data "{\"content\": \"${DISCORD_MESSAGE}\"}" \
        "${WEBHOOK_URL}"
        
    echo "Message sent successfully."
fi
