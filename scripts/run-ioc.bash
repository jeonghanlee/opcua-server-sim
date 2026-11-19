#!/usr/bin/env bash
# Prepare and run the demo IOC against the local composite simulator.

set -euo pipefail

readonly MODEL_DIR="models/s7-1500-composite"
readonly STARTUP_DIR="ioc"
readonly WORK_DIR="work"
readonly OPC_PORT=4840
readonly CA_PORT=5164

if (( $# != 0 )); then
    printf '%s\n' 'Usage: bash scripts/run-ioc.bash' >&2
    exit 2
fi

if [[ -z "${EPICS_BASE:-}" || -z "${EPICS_HOST_ARCH:-}" || -z "${EPICS_MODULES:-}" ]]; then
    printf '%s\n' 'Source the EPICS distribution setEpicsEnv.bash before starting the IOC.' >&2
    exit 1
fi

ioc_shell="${EPICS_BASE}/bin/${EPICS_HOST_ARCH}/iocsh.bash"
if [[ ! -x "${ioc_shell}" ]]; then
    printf 'IOC loader is missing or not executable: %s\n' "${ioc_shell}" >&2
    exit 1
fi

repo_path="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
model_path="${repo_path}/${MODEL_DIR}"
server_cert="${model_path}/pki/server-cert.der"
if [[ ! -s "${server_cert}" ]]; then
    printf '%s\n' 'Server certificate is missing. Start the demo server first.' >&2
    exit 1
fi
if ! read -r _ username password < <(grep -m 1 '^user[[:blank:]]' "${model_path}/simulation.conf"); then
    printf '%s\n' 'Demo user is missing from the simulation file.' >&2
    exit 1
fi

umask 077
mkdir -p -- "${repo_path}/${WORK_DIR}"
ioc_path="$(mktemp -d "${repo_path}/${WORK_DIR}/ioc.XXXXXX")"
cd -- "${ioc_path}"
mkdir -p pki/trusted/certs pki/issuers/certs
cp -- "${server_cert}" pki/trusted/certs/
openssl req -x509 -newkey rsa:2048 -noenc -subj /O=ioc -keyout key.pem -out cert.pem \
    -addext "subjectAltName=URI:urn:ioc@${HOSTNAME}:EPICS:IOC"
printf 'user=%s\npass=%s\n' "${username}" "${password}" > ident.txt

export SIM_IOC_DIR="${repo_path}/${STARTUP_DIR}"
export SIM_OPC_PORT="${OPC_PORT}" SIM_SECURE_DIR="${ioc_path}"
export EPICS_CAS_INTF_ADDR_LIST=127.0.0.1 EPICS_CAS_SERVER_PORT="${CA_PORT}"
exec "${ioc_shell}" -S "${SIM_IOC_DIR}/st.cmd"
