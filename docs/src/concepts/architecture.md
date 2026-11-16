# The architecture of the simulator

The simulator is a generic OPC UA (Open Platform Communications Unified Architecture) server that holds no device knowledge. The device comes from files: a server configuration, NodeSet2 XML (Extensible Markup Language) files, and an optional simulation file. This page explains the parts of the repository and the order in which the server uses its files.

## Parts of the repository

| Part | Location | Role |
| --- | --- | --- |
| Server | `src/opcua_server_sim.c` | The program `opcua-server-sim`. It builds on the open62541 library, release 1.5.10, with the NodeSet loader and the Alarms and Conditions support. |
| Probe | `tools/opcua-probe.c` | The program `opcua-probe`, a client that reads, writes, browses, and calls a running server. |
| NodeSet generator | `tools/simatic-nodeset.pl` | A Perl tool that writes the NodeSet2 XML file of a model from its description `plc.json`. |
| Interface NodeSet generator | `tools/server-interface-nodeset.pl` | A Perl tool that writes the NodeSet2 XML file of a user-defined server interface from a JSON description of its folders, objects, and variables. |
| Run script | `scripts/run-model.bash` | A Bash script that starts the server from a model directory. |
| Model | `models/<model>/` | The files of one device: `server.json5`, the NodeSet2 XML file, `plc.json`, `simulation.conf`, and `pki.cnf`. |
| Build system | `Makefile`, `configure/` | GNU Make files that build the programs and run the server and the tests. |
| Tests | `t/` | Perl tests that run under `prove`: for the server, the two NodeSet generators, the run script, an EPICS (Experimental Physics and Industrial Control System) IOC (input output controller), and the command check of the book. |
| Command check | `tools/doc-check.pl` | A Perl tool that runs the commands of the pages of this book and compares their output with the pages. |
| Mutation check | `tools/mutation-check.pl` | A Perl tool that proves the tests can fail: it applies the faults of a table to a copy of the tree and runs the tests on each copy. |
| IOC files | `ioc/` | A startup script and a database for an EPICS IOC that reads the model. |

## Start of the server

The server takes a server configuration file, then NodeSet2 files in load order, and the option `-s` with a simulation file. At start it does the following in order:

- It reads the configuration file and creates the server from it.
- It loads each NodeSet2 file in command-line order. The order fixes the namespace indices.
- It puts the build number, the software version, and the build date into the BuildInfo of the Server object.
- It prepares the Variables of the model and logs the namespace table.
- When a simulation file is named, it reads that file and schedules the simulation step.
- It runs until it receives an interrupt.

The target `make run` starts the server from the model directory, so that the configuration can name its certificate files relative to that directory.

## Files of a model

| File | Used by | Content |
| --- | --- | --- |
| `server.json5` | The server | Identity, limits, and security policies. |
| `<model>.NodeSet2.xml` | The server | The information model. |
| `plc.json` | The NodeSet generator | The description from which the NodeSet is written. |
| `simulation.conf` | The server | Behavior over time, alarms, methods, and user accounts. |
| `pki.cnf` | The target `certificate` | The request for the self-signed server certificate. |

## Pages that build on this concept

- [The role of a simulation file in the server](simulation-file.md) describes the behavior part.
- [Run the simulator](../procedures/run.md) starts the server.
- [Server configuration keys](../reference/server-config.md) lists the configuration file.
