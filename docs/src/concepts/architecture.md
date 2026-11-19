# Simulator architecture

The server uses configuration and model files to present an OPC UA device. The probe, EPICS IOC, and other OPC UA clients connect to the same server address.

## Files of a model

| File in `models/<model>/` | Role |
| --- | --- |
| `server.json5` | Server identity, endpoint, limits, and security policies. |
| `<model>.NodeSet2.xml` | Nodes and types served by the simulator. |
| `simulation.conf` | Optional rules for values, alarms, methods, and user accounts. |
| `plc.json` and `nodeset/` | Inputs to the NodeSet generator for the composite model. |
| `pki.cnf` | Request used to create the server certificate. |

## Server startup sequence

1. Read `server.json5` and create the open62541 server.
2. Load the NodeSet2 files in command-line order. That order determines the namespace indices.
3. Set the server's BuildInfo and prepare the model variables.
4. Apply the simulation file supplied with `-s`, then start serving requests.

`make run` starts the process in the model directory so that relative paths in the configuration resolve there. See [Run the simulator](../procedures/run.md).

## Tools and clients

| Tool | Role |
| --- | --- |
| `opcua-server-sim` | Serve the model and run its simulation. |
| `opcua-probe` | Browse, read, write, or call nodes on a running server. |
| `ioc/st.cmd` and `ioc/composite.db` | Connect the EPICS IOC to the same model and expose selected values over Channel Access. |
| `tools/simatic-nodeset.pl` | Generate the composite NodeSet from `plc.json` and XML sections. |
| `tools/server-interface-nodeset.pl` | Generate a user-defined interface from a JSON description of folders, objects, and variables. |
| `Makefile` and `configure/` | Build the programs and run the server, tests, and documentation checks. |
