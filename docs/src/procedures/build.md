# Build the server and the probe

The simulator is one C program, `opcua-server-sim`, and its client `opcua-probe` is a second program that reads and writes a running server. This procedure compiles both with the shipped compiler flags.

## Prerequisites

- A Linux host with `cc` and `make` in `PATH`.
- An installation of open62541 1.5.10 that has the NodeSet loader and the Alarms and Conditions support. To build one, clone `https://github.com/jeonghanlee/open62541-env` into the directory `../open62541-env`, install the packages `build-essential`, `git`, `pkg-config`, `cmake`, `python3`, `libssl-dev`, and `libxml2-dev` (Debian names), and run `make open62541 OPEN62541_PATH=<open62541_install_path>` with an install path that you can write to. The checkout must pass `CMAKE_EXTRA_OPTIONS` to cmake and carry the patch for open62541 1.5.10; otherwise `make build` stops with a message that names the missing feature. The target downloads the open62541 source, so it needs network access. [Make targets and variables](../reference/make.md) lists its variables.
- The path of that installation, which this page names `<open62541_install_path>`. It is the directory that holds `include/open62541` and `lib`.

1. In the repository root, build the server. The command compiles `src/opcua_server_sim.c` into `build/opcua-server-sim`:

   ```bash
   make build OPEN62541_PATH=<open62541_install_path>
   ```

   `<open62541_install_path>` is the installation path of open62541.

2. In the repository root, build the probe. The command compiles `tools/opcua-probe.c` into `build/opcua-probe`:

   ```bash
   make probe OPEN62541_PATH=<open62541_install_path>
   ```

## Verification

List the build directory. It holds the two programs and the file `identity` that records the commit the programs are built for:

```bash
ls build
```

The command prints:

```
identity
opcua-probe
opcua-server-sim
```
