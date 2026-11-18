# Build the server and the probe

The simulator is one C program, `opcua-server-sim`, and its client `opcua-probe` is a second program that reads and writes a running server. This procedure compiles both with the shipped compiler flags.

## Prerequisites

- A Linux host with `cc` and `make` in `PATH`.
- An installation of open62541 1.5.10 that has the NodeSet loader and the Alarms and Conditions support. [Install open62541 for the simulator](open62541.md) builds one. When the installation lacks a required feature, `make build` stops with a message that names it.
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
