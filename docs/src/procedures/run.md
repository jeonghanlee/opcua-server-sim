# Run the simulator

Start the default `s7-1500-composite` model and confirm that its simulated CPU reports RUN.

## Prerequisites

- [Install open62541](open62541.md). Use its absolute installation directory for `<open62541_install_path>`.
- For `<ua_nodeset_path>`, use the absolute path of `open62541-src/deps/ua-nodeset` inside your `open62541-env` checkout. The install script puts that checkout in `work/open62541-env-1.5`.
- Have `perl` and `openssl` available and keep TCP port 4840 free. Use two terminals at the checkout root.

1. In terminal one, build and start the server. The target prepares the NodeSet and certificate when needed. Leave the server running when it opens port 4840.

   <!-- doc-check: background ready=Creating listen socket.*port 4840 -->
   ```bash
   make run OPEN62541_PATH="<open62541_install_path>" UA_NODESET_PATH="<ua_nodeset_path>"
   ```

2. In terminal two, build the probe.

   ```bash
   make probe OPEN62541_PATH="<open62541_install_path>"
   ```

## Verification

In terminal two, read the operating mode. The value `8` means RUN.

```bash
build/opcua-probe opc.tcp://127.0.0.1:4840 read 'ns=3;s=OperatingMode'
```

Expected output.

```
Good 8
```

Press Ctrl+C in terminal one to stop the server.

If you need a different model or simulation file, see [Make targets and variables](../reference/make.md). Use an absolute path for `MODEL_SIMULATION`, or set it to an empty value to start without simulation. To use the run script for the default model, see the [Quick Start](https://github.com/jeonghanlee/opcua-server-sim/blob/master/docs/QUICKSTART.md).
