#!/usr/bin/env bash
# Build and install open62541 under the repository's work directory.

set -euo pipefail

readonly ENV_URL="https://github.com/jeonghanlee/open62541-env"
readonly ENV_BRANCH="1.5"
readonly ENV_DIR="work/open62541-env-1.5"
readonly INSTALL_DIR="work/open62541-1.5.10"

repo_path="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
env_path="${repo_path}/${ENV_DIR}"
install_path="${repo_path}/${INSTALL_DIR}"

if [[ ! -e "${env_path}" ]]; then
    git -C "${repo_path}" clone --branch "${ENV_BRANCH}" "${ENV_URL}" "${env_path}"
fi

make -C "${repo_path}" open62541 OPEN62541_ENV_PATH="${env_path}" OPEN62541_PATH="${install_path}"
make -C "${repo_path}" check-open62541 OPEN62541_PATH="${install_path}"
printf 'Installed open62541 in %s\n' "${install_path}"
