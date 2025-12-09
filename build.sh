#!/usr/bin/env bash
set -euo pipefail

ARCHIVE_URL="https://github.com/MiSTer-unstable-nightlies/Build-Automation_MiSTer/archive/main.zip"

echo "Unpacking ${ARCHIVE_URL}"
BUILD_AUTOMATION_DIR_TMP=$(mktemp -d)
wget -q -O "${BUILD_AUTOMATION_DIR_TMP}/tmp.zip" "${ARCHIVE_URL}"

unzip -q "${BUILD_AUTOMATION_DIR_TMP}/tmp.zip" -d "${BUILD_AUTOMATION_DIR_TMP}"

echo
echo "Arguments"
if [[ "${PROJECT_NAME:-}" == "" ]] ; then
    PROJECT_NAME="${REPOSITORY##*/}"
fi
echo "PROJECT_NAME: ${PROJECT_NAME}"

source <(cat "${BUILD_AUTOMATION_DIR_TMP}/Build-Automation_MiSTer-main/repositories.ini" | python3 -c "
import sys, configparser
config = configparser.ConfigParser()
config.read_file(sys.stdin)
if config.has_section('${PROJECT_NAME}'):
    for var in config['${PROJECT_NAME}'].keys():
        print('%s=\${%s:-\"%s\"}' % (var.upper(), var.upper(), config['${PROJECT_NAME}'][var].strip('\"')))
")

if [[ "${DISPATCH_URL:-}" == "" ]] ; then
    DISPATCH_URL="https://api.github.com/repos/MiSTer-unstable-nightlies/Build-Automation_MiSTer/actions/workflows/listen_releases.yml/dispatches"
fi
echo "DISPATCH_URL: ${DISPATCH_URL}"

if [[ "${DISPATCH_REF:-}" == "" ]] ; then
    DISPATCH_REF="refs/heads/main"
fi
echo "DISPATCH_REF: ${DISPATCH_REF}"

if [[ "${BUILD_INDEX:-}" == "" ]] ; then
    BUILD_INDEX="0"
fi
echo "BUILD_INDEX: ${BUILD_INDEX}"

if [[ "${RELEASE_TAG:-}" == "" ]] ; then
    RELEASE_TAG="unstable-builds"
fi
echo "RELEASE_TAG: ${RELEASE_TAG}"

if [[ "${CORE_NAME:-}" == "" ]] ; then
    CORE_NAME="${PROJECT_NAME%%???????}"
fi
echo "CORE_NAME: ${CORE_NAME}"

if [[ "${RELEASE_NAME:-}" == "" ]] ; then
    RELEASE_NAME="${CORE_NAME}"
fi
echo "RELEASE_NAME: ${RELEASE_NAME}"

if [[ "${DOCKER_IMAGE:-}" == "" ]] ; then
    DOCKER_IMAGE="theypsilon/quartus-lite-c5:17.0.2.docker0"
fi
echo "DOCKER_IMAGE: ${DOCKER_IMAGE}"

if [[ "${DOCKER_FOLDER:-}" == "" ]] ; then
    DOCKER_FOLDER="."
fi
echo "DOCKER_FOLDER: ${DOCKER_FOLDER}"

if [[ "${COMPILATION_COMMAND:-}" == "" ]] ; then
    COMPILATION_COMMAND="/opt/intelFPGA_lite/quartus/bin/quartus_sh --flow compile ${CORE_NAME}.qpf"
fi
echo "COMPILATION_COMMAND: ${COMPILATION_COMMAND}"

if [[ "${COMPILATION_OUTPUT:-}" == "" ]] ; then
    COMPILATION_OUTPUT="output_files/${CORE_NAME}.rbf"
fi
echo "COMPILATION_OUTPUT: ${COMPILATION_OUTPUT}"

if [[ "${RANDOMIZE_SEED:-}" == "" ]] ; then
    RANDOMIZE_SEED=""
fi
echo "RANDOMIZE_SEED: ${RANDOMIZE_SEED}"

if [[ "${SKIP_DIFF_CHECK:-}" == "" ]] ; then
    SKIP_DIFF_CHECK="false"
else
    SKIP_DIFF_CHECK="${SKIP_DIFF_CHECK,,}"
fi
echo "SKIP_DIFF_CHECK: ${SKIP_DIFF_CHECK}"

if [[ "${EXTRA_DOCKERIGNORE_LINE:-}" == "" ]] ; then
    EXTRA_DOCKERIGNORE_LINE=""
fi
echo "EXTRA_DOCKERIGNORE_LINE: ${EXTRA_DOCKERIGNORE_LINE}"

cp "${BUILD_AUTOMATION_DIR_TMP}/Build-Automation_MiSTer-main/templates/Dockerfile" .
cp "${BUILD_AUTOMATION_DIR_TMP}/Build-Automation_MiSTer-main/templates/Dockerfile.file-filter" .
cp "${BUILD_AUTOMATION_DIR_TMP}/Build-Automation_MiSTer-main/templates/.dockerignore" "${DOCKER_FOLDER}"

rm -rf "${BUILD_AUTOMATION_DIR_TMP}"

if [[ "${EXTRA_DOCKERIGNORE_LINE}" != "" ]] ; then
    echo "${EXTRA_DOCKERIGNORE_LINE}" >> "${DOCKER_FOLDER}/".dockerignore
    echo >> "${DOCKER_FOLDER}/".dockerignore
fi

FILE_EXTENSION="${COMPILATION_OUTPUT##*.}"
RELEASE_FILE="${CORE_NAME}_unstable_$(date +%Y%m%d)_$(date +%H)${GITHUB_SHA:0:4}"
if [[ "${FILE_EXTENSION}" != "${COMPILATION_OUTPUT}" ]] ; then
    RELEASE_FILE="${RELEASE_FILE}.${FILE_EXTENSION}"
fi

echo
echo "Current commit: ${GITHUB_SHA}"

LAST_RELEASE_FILE=
if [ -d releases/ ] ; then
    LAST_RELEASE_FILE=$(cd releases/ ; git ls-files -z | xargs -0 -I{} -- git log -1 --format="%ai {}" {} | grep "${RELEASE_NAME}" | sort | tail -n1 | awk '{ print substr($0, index($0,$4)) }') || true
fi

git fetch origin --unshallow 2> /dev/null || true
git submodule update --init --recursive

echo
echo "Grabbing current files..."

CURRENT_BUILD_FOLDER_TMP=$(mktemp -d)
docker build -f Dockerfile.file-filter -t filtered_files "${DOCKER_FOLDER}"
docker cp $(docker create --rm filtered_files):/files "${CURRENT_BUILD_FOLDER_TMP}/"
CURRENT_BUILD_DIR="${CURRENT_BUILD_FOLDER_TMP}/files"
PREVIOUS_BUILD_ZIP="LatestBuild${CORE_NAME}.zip"

if [[ "${SKIP_DIFF_CHECK}" != "true" ]] ; then

    FIND_DIFFERENCES_BETWEEN_DIRECTORIES_RET=
    find_differences_between_directories()
    {
        local CURRENT_BUILD_DIR="${1}"
        local OTHER_BUILD_DIR="${2}"

        local CHANGES_DETECTED="false"
        local CURRENT_BUILD_FILES_TMP=$(mktemp)
        local OTHER_BUILD_FILES_TMP=$(mktemp)

        pushd "${CURRENT_BUILD_DIR}" > /dev/null
        find . > "${CURRENT_BUILD_FILES_TMP}"
        popd > /dev/null
        pushd "${OTHER_BUILD_DIR}" > /dev/null
        find . > "${OTHER_BUILD_FILES_TMP}"
        popd > /dev/null

        local CURRENT_BUILD_QTY=$(cat "${CURRENT_BUILD_FILES_TMP}" | wc -l | awk '{print $1}')
        local OTHER_BUILD_QTY=$(cat "${OTHER_BUILD_FILES_TMP}" | wc -l | awk '{print $1}')

        if ! git diff --exit-code "${OTHER_BUILD_FILES_TMP}" "${CURRENT_BUILD_FILES_TMP}" ; then
            CHANGES_DETECTED="true"

            echo
            echo "Found differences"
            echo "Current build #files: ${CURRENT_BUILD_QTY}"
            echo "Other build #files: ${OTHER_BUILD_QTY}"
        else
            local CHANGED_FILES=()
            while IFS="" read -r line || [ -n "${line}" ]
            do
                LINE_PATH_1="${OTHER_BUILD_DIR}/${line}"
                LINE_PATH_2="${CURRENT_BUILD_DIR}/${line}"

                if [ ! -f "${LINE_PATH_1}" ] && [ ! -f "${LINE_PATH_2}" ] ; then continue ; fi
                if [ ! -f "${LINE_PATH_2}" ] ; then echo "UNEXPECTED: File ${LINE_PATH_2} doesn't exist!" ; exit 1 ; fi
                if [ ! -f "${LINE_PATH_1}" ] ; then echo "UNEXPECTED: File ${LINE_PATH_1} doesn't exist!" ; exit 1 ; fi

                if ! git diff --exit-code --ignore-space-at-eol "${LINE_PATH_1}" "${LINE_PATH_2}" ; then
                    echo
                    echo "Found differences"
                    echo
                    CHANGED_FILES+=( "${line}" )
                fi
            done < "${CURRENT_BUILD_FILES_TMP}"

            if [ ${#CHANGED_FILES[@]} -ge 1 ] ; then
                CHANGES_DETECTED="true"
                echo "Following files have changes: "
                for changed_file in "${CHANGED_FILES[@]}"
                do
                    echo "${changed_file}"
                done
            fi
        fi

        rm -rf "${CURRENT_BUILD_FILES_TMP}"
        rm -rf "${OTHER_BUILD_FILES_TMP}"
        FIND_DIFFERENCES_BETWEEN_DIRECTORIES_RET="${CHANGES_DETECTED}"
    }

    DIFFERENCES_FOUND_WITH_LATEST_RELEASE="true"
    if [[ "${LAST_RELEASE_FILE}" == "" ]] ; then
        echo
        echo "No release files in this repository"
    else
        echo
        echo "Found latest release: ${LAST_RELEASE_FILE}"
        LAST_RELEASE_COMMIT=$(git log -n 1 --pretty=format:%H -- "releases/${LAST_RELEASE_FILE}")
        echo "    @ commit: ${LAST_RELEASE_COMMIT}"
        echo
        echo "Grabbing latest release files..."

        git checkout -f "${LAST_RELEASE_COMMIT}" > /dev/null 2>&1 
        LAST_RELEASE_FOLDER_TMP=$(mktemp -d)
        docker build -f Dockerfile.file-filter -t filtered_files "${DOCKER_FOLDER}"
        docker cp $(docker create --rm filtered_files):/files "${LAST_RELEASE_FOLDER_TMP}/"
        LAST_RELEASE_DIR="${LAST_RELEASE_FOLDER_TMP}/files"

        git checkout -f "${GITHUB_SHA}" > /dev/null 2>&1

        echo
        echo "Calculating differences with latest release..."

        find_differences_between_directories "${CURRENT_BUILD_DIR}" "${LAST_RELEASE_DIR}"
        DIFFERENCES_FOUND_WITH_LATEST_RELEASE="${FIND_DIFFERENCES_BETWEEN_DIRECTORIES_RET}"
        rm -rf "${LAST_RELEASE_FOLDER_TMP}"
        echo "Differences found with latest release: ${DIFFERENCES_FOUND_WITH_LATEST_RELEASE}"
    fi

    echo
    echo "Grabbing files from latest unstable build..."
    export GITHUB_TOKEN="${GITHUB_TOKEN}"
    if gh release download "${RELEASE_TAG}" --pattern "${PREVIOUS_BUILD_ZIP}" 2> /dev/null ; then
        PREVIOUS_BUILD_DIR_TMP=$(mktemp -d)
        unzip -q "${PREVIOUS_BUILD_ZIP}" -d "${PREVIOUS_BUILD_DIR_TMP}"
        rm "${PREVIOUS_BUILD_ZIP}"
        echo "Done."
    else
        echo "No previous unstable build found."
    fi

    echo
    echo "Calculating differences with previous unstable build..."
    DIFFERENCES_FOUND_WITH_PREVIOUS_BUILD="true"
    if [[ "${PREVIOUS_BUILD_DIR_TMP:-}" != "" ]] ; then
        find_differences_between_directories "${CURRENT_BUILD_DIR}" "${PREVIOUS_BUILD_DIR_TMP}"
        DIFFERENCES_FOUND_WITH_PREVIOUS_BUILD="${FIND_DIFFERENCES_BETWEEN_DIRECTORIES_RET}"
        rm -rf "${PREVIOUS_BUILD_DIR_TMP}"
    else
        echo "There wasn't a previous unstable build!"
    fi
    echo "Differences found with previous unstable build: ${DIFFERENCES_FOUND_WITH_PREVIOUS_BUILD}"

    if [[ "${DIFFERENCES_FOUND_WITH_LATEST_RELEASE}" != "true" ]] || [[ "${DIFFERENCES_FOUND_WITH_PREVIOUS_BUILD}" != "true" ]] ; then
        rm -rf "${CURRENT_BUILD_FOLDER_TMP}" 2> /dev/null || true
        echo
        if [[ "${DIFFERENCES_FOUND_WITH_LATEST_RELEASE}" != "true" ]] ; then
            echo "No changes detected since the latest release from upstream."
        else
            echo "No changes detected since latest unstable build."
        fi
        echo "Skipping..."
        exit 0
    fi
fi

echo
echo "Zipping current files to prepare next LastBuild.zip file..."
pushd "${CURRENT_BUILD_DIR}" > /dev/null
zip -q -9 -r "${PREVIOUS_BUILD_ZIP}" .
popd > /dev/null

echo
echo "Creating release ${RELEASE_FILE}"

sed -i "s%<<DOCKER_IMAGE>>%${DOCKER_IMAGE}%g" Dockerfile
sed -i "s%<<COMPILATION_COMMAND>>%${COMPILATION_COMMAND}%g" Dockerfile
sed -i "s%<<COMPILATION_OUTPUT>>%${COMPILATION_OUTPUT}%g" Dockerfile

if [[ "${RANDOMIZE_SEED}" != "" ]] ; then
    RND="$RANDOM"
    echo "RANDOM SEED: ${RND}"
    echo >> "${RANDOMIZE_SEED}"
    echo "set_global_assignment -name SEED ${RND}" >> "${RANDOMIZE_SEED}"
fi

docker buildx create --bootstrap --use --name buildkit-unlimited-logs \
    --driver-opt env.BUILDKIT_STEP_LOG_MAX_SIZE=-1 \
    --driver-opt env.BUILDKIT_STEP_LOG_MAX_SPEED=-1
docker buildx build -f Dockerfile -t artifact \
    --output "type=local,dest=build_artifact_output,include=/project/${COMPILATION_OUTPUT}" "${DOCKER_FOLDER}" 2>&1 | tee docker-build.log

echo cp "build_artifact_output/${COMPILATION_OUTPUT}" "${RELEASE_FILE}"
cp "build_artifact_output/${COMPILATION_OUTPUT}" "${RELEASE_FILE}"

RELEASE_FILE_URL="https://github.com/${REPOSITORY}/releases/download/${RELEASE_TAG}/${RELEASE_FILE}"
echo "Uploading release to ${RELEASE_FILE_URL}"

if ! gh release list | grep -q "${RELEASE_TAG}" ; then
    gh release create "${RELEASE_TAG}" -p || true
    sleep 15s
fi

sleep $((BUILD_INDEX * 150))

if gh release view "${RELEASE_TAG}" | grep -q "${RELEASE_FILE}" ; then
    echo
    echo "Release already uploaded."
    exit 0
fi

echo "${GITHUB_SHA}" > commit.txt

gh release upload "${RELEASE_TAG}" "${RELEASE_FILE}" --clobber
gh release upload "${RELEASE_TAG}" "${CURRENT_BUILD_DIR}/${PREVIOUS_BUILD_ZIP}" --clobber
gh release upload "${RELEASE_TAG}" docker-build.log --clobber
gh release upload "${RELEASE_TAG}" commit.txt --clobber

rm -rf "${CURRENT_BUILD_FOLDER_TMP}" 2> /dev/null || true

echo "Release uploaded successfully."

if [[ "${DISPATCH_TOKEN:-}" != "" ]] ; then
    COMMIT_TO_USE="${GITHUB_SHA}"
    while true; do
        CHANGED_FILES=$(git diff-tree --no-commit-id --name-only -r "${COMMIT_TO_USE}" 2>/dev/null || echo "")
        NON_WORKFLOW_FILES=$(echo "${CHANGED_FILES}" | grep -v '^\.github/workflows/' || echo "")

        if [[ -n "${NON_WORKFLOW_FILES}" ]] ; then
            break
        fi

        # No non-workflow files (either empty commit or only workflow files). Try parent commit
        COMMIT_TO_USE=$(git rev-parse "${COMMIT_TO_USE}^" 2>/dev/null || echo "")
        if ! git rev-parse --verify "${COMMIT_TO_USE}" >/dev/null 2>&1 ; then
            COMMIT_TO_USE="${GITHUB_SHA}"
            break
        fi
    done

    echo "Using commit for message: ${COMMIT_TO_USE}/${GITHUB_SHA}"

    COMMIT_MESSAGE_HEADER="$(git log --pretty='format:[%an %as %h]' -n1 ${COMMIT_TO_USE})"
    COMMIT_MESSAGE_BODY="$(git log --pretty='%B' -n1 ${COMMIT_TO_USE})"
    if [[ $COMMIT_MESSAGE_BODY == *$'\n'* ]] ; then
        COMMIT_MESSAGE="${COMMIT_MESSAGE_HEADER}\n${COMMIT_MESSAGE_BODY}"
    else
        COMMIT_MESSAGE="${COMMIT_MESSAGE_HEADER} ${COMMIT_MESSAGE_BODY}"
    fi
    COMMIT_MESSAGE="${COMMIT_MESSAGE//$'\n'/\\n}"
    COMMIT_MESSAGE="${COMMIT_MESSAGE//\"/\'}"
    COMMIT_MESSAGE="${COMMIT_MESSAGE//$'\r'/}"
    COMMIT_MESSAGE="${COMMIT_MESSAGE//$'\t'/    }"
    echo "COMMIT_MESSAGE: ${COMMIT_MESSAGE}"

    CLIENT_PAYLOAD="\"release_file_url\":\"${RELEASE_FILE_URL}\""
    CLIENT_PAYLOAD+=",\"core_name\":\"${CORE_NAME}\""
    CLIENT_PAYLOAD+=",\"repository\":\"${REPOSITORY}\""
    CLIENT_PAYLOAD+=",\"release_tag\":\"${RELEASE_TAG}\""
    CLIENT_PAYLOAD+=",\"commit_sha\":\"${GITHUB_SHA}\""
    CLIENT_PAYLOAD+=",\"commit_msg\":\"${COMMIT_MESSAGE}\""

    DATA_JSON="{\"ref\":\"${DISPATCH_REF}\",\"inputs\":{${CLIENT_PAYLOAD}}}"
    
    echo
    echo "Sending dispatch event to ${DISPATCH_URL}:${DISPATCH_REF} with payload:"
    echo "${DATA_JSON}"
    echo

    curl --fail --output /dev/null \
        -X POST \
        -H "Authorization: token ${DISPATCH_TOKEN}" \
        -H "Accept: application/vnd.github.v3+json" \
        -H "Content-Type: application/json" \
        --data "${DATA_JSON}" \
        "${DISPATCH_URL}"
        
    echo "Event sent successfully."
fi
