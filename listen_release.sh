#!/usr/bin/env bash
set -euo pipefail

echo "Arguments"
echo "RELEASE_FILE_URL: ${RELEASE_FILE_URL}"
echo "CORE_NAME: ${CORE_NAME}"
echo "REPOSITORY: ${REPOSITORY}"
echo "RELEASE_TAG: ${RELEASE_TAG}"
echo "COMMIT_SHA: ${COMMIT_SHA}"

echo "1"
COMMIT_MESSAGE="${COMMIT_MESSAGE//$'\n'/\\n}"
echo "2"
COMMIT_MESSAGE="${COMMIT_MESSAGE//\"/\'}"
echo "3"
COMMIT_MESSAGE=$(echo "${COMMIT_MESSAGE}" | sed -e 's/\([\]n\)*[(]cherry picked from commit \([a-f0-9]*\)[)]$//g')
echo "4"
END_OF_LINES=$(echo $COMMIT_MESSAGE | grep -o '\\n' | wc -l)
echo "5"
if [[ "${END_OF_LINES}" == "1" ]] && [[ "${COMMIT_MESSAGE}" =~ ^[\[].*[\]][\\n].*$ ]] ; then
    echo "6"
    COMMIT_MESSAGE="${COMMIT_MESSAGE/\\n/ }"
fi
echo "COMMIT_MESSAGE: ${COMMIT_MESSAGE}"

DISCORD_MESSAGE="Latest **${CORE_NAME}** unstable build: ${RELEASE_FILE_URL}"
DISCORD_MESSAGE+="\n"
DISCORD_MESSAGE+="\`\`\`${COMMIT_MESSAGE}\`\`\`"

echo
echo "Discord message:"
echo "${DISCORD_MESSAGE}"
echo

if [[ "${WEBHOOK_URL:-}" != "" ]] ; then

    curl \
        --fail \
        --output /dev/null \
        -i \
        -H "Accept: application/json" \
        -H "Content-Type:application/json" \
        -X POST \
        --data "{\"content\": \"${DISCORD_MESSAGE}\"}" \
        "${WEBHOOK_URL}"
        
    echo "Message sent to MiSTer official Discord successfully."
fi
