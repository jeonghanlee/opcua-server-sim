#!/usr/bin/env bash
#
# Runs the server from a model directory: the directory holds server.json5,
# exactly one NodeSet XML file, and optionally simulation.conf. The server
# starts in that directory, as "make run" starts it, so that the server
# configuration can name files relative to the directory.
#
# usage: run-model.bash [--di <file>] <model-directory>
#
# --di <file>  loads this DI NodeSet before the NodeSet of the directory.
#
# Exit status: 1 for a missing or ambiguous file, 2 for a usage error. After a
# successful start the exit status is the one of the server.

set -euo pipefail

# Server binary that "make build" writes, relative to the directory of the
# repository that holds this script.
readonly SERVER_RELATIVE="build/opcua-server-sim"

# File names the model directory holds.
readonly CONFIG_NAME="server.json5"
readonly SIMULATION_NAME="simulation.conf"

readonly EXIT_ERROR=1
readonly EXIT_USAGE=2

# Prints the usage text to the file descriptor given as the argument.
function usage {
    local fd="$1"
    printf "%s\n" "usage: run-model.bash [--di <file>] <model-directory>" >&"$fd"
    return 0
}

# Prints an error message and exits with the error status.
function fail {
    printf "run-model.bash: %s\n" "$1" >&2
    exit "$EXIT_ERROR"
}

function main {
    local di=""
    local top server model config nodeset simulation
    local -a xml_files

    while (( $# > 0 )); do
        case "$1" in
            -h|--help)
                usage 1
                exit 0
                ;;
            --di)
                (( $# >= 2 )) || { usage 2; exit "$EXIT_USAGE"; }
                di="$2"
                shift 2
                ;;
            --)
                shift
                break
                ;;
            -*)
                usage 2
                exit "$EXIT_USAGE"
                ;;
            *)
                break
                ;;
        esac
    done
    (( $# == 1 )) || { usage 2; exit "$EXIT_USAGE"; }
    model="$1"

    top="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    server="${top}/${SERVER_RELATIVE}"
    [[ -x "$server" ]] || fail "$server is not built: run make build"
    [[ -d "$model" ]] || fail "$model is not a directory"
    model="$(cd "$model" && pwd)"

    config="${model}/${CONFIG_NAME}"
    [[ -f "$config" ]] || fail "$model holds no ${CONFIG_NAME}"

    shopt -s nullglob
    xml_files=("${model}"/*.xml)
    shopt -u nullglob
    if (( ${#xml_files[@]} == 0 )); then
        fail "$model holds no NodeSet XML file"
    elif (( ${#xml_files[@]} > 1 )); then
        fail "$model holds ${#xml_files[@]} XML files, name one directory per model: ${xml_files[*]##*/}"
    fi
    nodeset="${xml_files[0]}"

    local -a command=("$server")
    simulation="${model}/${SIMULATION_NAME}"
    if [[ -f "$simulation" ]]; then
        command+=(-s "$simulation")
    fi
    command+=("$config")
    if [[ -n "$di" ]]; then
        [[ -f "$di" ]] || fail "$di is not a file"
        command+=("$(cd "$(dirname "$di")" && pwd)/$(basename "$di")")
    fi
    command+=("$nodeset")

    cd "$model"
    exec "${command[@]}"
}

main "$@"
