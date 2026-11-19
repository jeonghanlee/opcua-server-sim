# Build the server and the probe

Build the simulator and its command-line OPC UA client, `opcua-probe`. Both binaries go in `build/`.

## Prerequisites

- A Linux host with `cc` and `make`.
- [Install open62541](open62541.md) with the features required by the simulator. Use its absolute installation directory for `<open62541_install_path>`. The default install script uses `work/open62541-1.5.10`.

1. From the checkout root, build the server.

   ```bash
   make build OPEN62541_PATH="<open62541_install_path>"
   ```

2. Build the probe if you want to check the server from the command line.

   ```bash
   make probe OPEN62541_PATH="<open62541_install_path>"
   ```

## Verification

After building both programs, list the two binaries.

```bash
ls build/opcua-probe build/opcua-server-sim
```

Expected output.

```
build/opcua-probe
build/opcua-server-sim
```

Continue with [Run the simulator](run.md).
