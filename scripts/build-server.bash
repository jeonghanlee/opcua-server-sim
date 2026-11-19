#!/usr/bin/env bash
# Build the simulator server against the open62541 installation in work.

set -euo pipefail

readonly INSTALL_DIR="work/open62541-1.5.10"
readonly NODESET_LOADER_HEADER="include/open62541/plugin/nodesetloader.h"
readonly INSTALL_SCRIPT="scripts/install-open62541.bash"

repo_path="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
install_path="${repo_path}/${INSTALL_DIR}"

if [[ ! -f "${install_path}/${NODESET_LOADER_HEADER}" ]]; then
    printf 'open62541 is missing from %s.\n' "${install_path}" >&2
    printf 'Install it first: bash %q\n' "${repo_path}/${INSTALL_SCRIPT}" >&2
    exit 1
fi

make -C "${repo_path}" build OPEN62541_PATH="${install_path}"
