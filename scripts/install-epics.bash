#!/usr/bin/env bash
# Install the EPICS binary distribution for the local operating system.

set -euo pipefail

readonly DIST_URL="https://github.com/jeonghanlee/EPICS-env-distribution"
readonly DIST_VERSION="1.5.0"
readonly BASE_VERSION="7.0.10"
readonly DIST_DIR="work/epics-dist"
readonly EPICS_LINK="work/epics"

if [[ "$(uname -m)" != x86_64 ]]; then
    printf '%s\n' 'This EPICS distribution requires an x86_64 host.' >&2
    exit 1
fi
os_id="$(
    # shellcheck source=/dev/null
    . /etc/os-release && printf '%s-%s' "${ID}" "${VERSION_ID}"
)"

repo_path="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
dist_path="${repo_path}/${DIST_DIR}"
epics_link="${repo_path}/${EPICS_LINK}"
dist_subdir="${DIST_VERSION}/${os_id}/${BASE_VERSION}"
install_path="${dist_path}/${dist_subdir}"

if [[ ! -e "${dist_path}" ]]; then
    git -C "${repo_path}" clone --depth 1 --filter=blob:none --sparse "${DIST_URL}" "${dist_path}"
fi

if [[ ! -d "${dist_path}/.git" ]]; then
    printf 'EPICS distribution checkout expected at %s\n' "${dist_path}" >&2
    exit 1
fi
origin_url="$(git -C "${dist_path}" config --get remote.origin.url)"
if [[ "${origin_url%.git}" != "${DIST_URL}" ]]; then
    printf 'Unexpected EPICS distribution origin at %s\n' "${dist_path}" >&2
    exit 1
fi

git -C "${dist_path}" sparse-checkout set "${dist_subdir}"
if [[ ! -r "${install_path}/setEpicsEnv.bash" || ! -d "${install_path}/modules/opcua" ]]; then
    printf 'No EPICS distribution with opcua is available for %s.\n' "${os_id}" >&2
    exit 1
fi

if [[ ! "${epics_link}" -ef "${install_path}" ]]; then
    ln -sT -- "${DIST_DIR##*/}/${dist_subdir}" "${epics_link}"
fi
printf 'Activate EPICS: source %q\n' "${epics_link}/setEpicsEnv.bash"
