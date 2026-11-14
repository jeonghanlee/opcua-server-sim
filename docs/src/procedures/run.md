# Run the simulator

The target `make run` starts the server with the composite model and its simulation file, and the server answers OPC UA (Open Platform Communications Unified Architecture) requests on port 4840. This procedure starts the server and reads one value from it with the probe.

## Prerequisites

- The prerequisites of [Build the server and the probe](build.md), and the path of the installation of open62541, which this page names `<open62541_install_path>`.
- The directory of the OPC Foundation NodeSet2 files, which this page names `<ua_nodeset_path>`. Give it as an absolute path, because the target starts the server from the model directory. The server loads `<ua_nodeset_path>/DI/Opc.Ua.Di.NodeSet2.xml`. After `make open62541`, the directory is `../open62541-env/open62541-src/deps/ua-nodeset`.
- `perl` and `openssl` in `PATH`, because the target writes the NodeSet and creates the server certificate when they are missing.
- TCP (Transmission Control Protocol) port 4840 free on the host.

1. In the repository root, build the server, create the certificate, and start the server. The command runs until you stop it with Ctrl+C, so run the next steps in a second terminal:

   <!-- doc-check: background ready=simulating \d+ signals -->
   ```bash
   make run OPEN62541_PATH=<open62541_install_path> UA_NODESET_PATH=<ua_nodeset_path>
   ```

   `<open62541_install_path>` is the installation path of open62541. `<ua_nodeset_path>` is the directory of the OPC Foundation NodeSet2 files.

   The server logs the namespace table when it has loaded the NodeSets. The namespace indices are fixed by the load order:

   ```
   [2026-11-13 16:13:54.216 (UTC-0800)] info/application	namespace 0: http://opcfoundation.org/UA/
   [2026-11-13 16:13:54.216 (UTC-0800)] info/application	namespace 1: urn:SIMATIC.S7-1500.OPC-UA.Application:PLC_1
   [2026-11-13 16:13:54.216 (UTC-0800)] info/application	namespace 2: http://opcfoundation.org/UA/DI/
   [2026-11-13 16:13:54.216 (UTC-0800)] info/application	namespace 3: http://www.siemens.com/simatic-s7-opcua
   ```

2. In the second terminal, in the repository root, build the probe:

   ```bash
   make probe OPEN62541_PATH=<open62541_install_path>
   ```

## Verification

Read the operating state of the simulated CPU (central processing unit) while the server runs. The value 8 means RUN:

```bash
build/opcua-probe opc.tcp://127.0.0.1:4840 read 'ns=3;s=OperatingMode'
```

The command prints the status name and the value:

```
Good 8
```

To stop the server, press Ctrl+C in the first terminal.

The server uses the model that the variable `MODEL` names and the simulation file that `MODEL_SIMULATION` names; give that file as an absolute path, for example the path of `simulation-1517-1518.conf`. [Make targets and variables](../reference/make.md) lists both. To run the server without a simulation file, add an empty `MODEL_SIMULATION=` to the command of step 1.
