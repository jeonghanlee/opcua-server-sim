# Make targets and variables

The build system is a GNU Make tree: the `Makefile` in the repository root includes the files of the directory `configure/`. This page lists the make targets and the variables that you can set on the command line or in a local settings file.

## Targets of the build system

The target `help` is the default target. Print the table of targets with:

```bash
make help
```

The command prints:

```
Usage: make <target> [VAR=value]

Target            Action
---------------   ------------------------------------------------------
open62541         Build and install open62541 through open62541-env
build             Build the server
probe             Build the client that checks a running server
nodeset           Write the NodeSet of a model from its plc.json
test              Run the tests: the tools, and the server with the model MODEL
book-check        Run the commands of the pages of the book and compare their output
certificate       Create the server certificate of a model that carries pki.cnf
run               Run the server with the model MODEL (default: s7-1500-composite)
clean             Remove the build directory
vars              Print the active configuration variables
```

| Target | Dependencies | Effect |
| --- | --- | --- |
| `open62541` | `open62541-env` checkout on the branch `1.5` | Builds and installs open62541 through `open62541-env` into `OPEN62541_PATH`. |
| `build` | open62541 check | Compiles `src/opcua_server_sim.c` into `build/opcua-server-sim`. |
| `probe` | open62541 check | Compiles `tools/opcua-probe.c` into `build/opcua-probe`. |
| `nodeset` | `perl`, `plc.json` of the model | Writes `<MODEL>.NodeSet2.xml` when the description, the XML (Extensible Markup Language) sections, or the tool are newer than it. |
| `certificate` | `openssl` | Creates the server key and the self-signed certificate of a model that carries `pki.cnf`. |
| `run` | `build`, `certificate`, `nodeset` | Starts the server from the model directory with the model `MODEL`. |
| `test` | `perl`, `prove`, `build`, `probe`, `certificate` | Runs the tests of the directory `t` with `prove`. |
| `book-check` | `perl`, `prove`, `git` | Runs the commands of the pages of the book in clean checkouts and compares their output with the pages. |
| `clean` | none | Removes the directory `build`. |
| `vars` | none | Prints the active configuration variables. |

The target `build` and the target `probe` stop with an error message when `OPEN62541_PATH` does not hold an open62541 installation with the NodeSet loader and the Alarms and Conditions support.

## Variables of the build system

Set a variable on the command line, as in `make build OPEN62541_PATH=<open62541_install_path>`. The defaults are in `configure/CONFIG_SITE`, `configure/RELEASE`, and `configure/CONFIG_VARS`.

| Variable | Default | Meaning |
| --- | --- | --- |
| `OPEN62541_PATH` | `/usr/local` | Installation prefix of open62541, the directory that holds `include` and `lib`. |
| `OPEN62541_ENV_PATH` | `../open62541-env` | Checkout of `open62541-env`, used by the target `open62541`. `open62541-env` is the repository `jeonghanlee/open62541-env` on GitHub, which builds and installs open62541; the target stops with an error when the checkout is missing. The checkout must be on the branch `1.5`, which builds open62541 1.5.10. |
| `OPEN62541_NAMESPACE_ZERO` | `FULL` | Namespace zero option that the target `open62541` passes to cmake. |
| `OPEN62541_ALARMS_CONDITIONS` | `ON` | Alarms and Conditions option that the target `open62541` passes to cmake. |
| `OPEN62541_CMAKE_OPTIONS` | NodeSet loader on, plus the two options above | cmake options that the target `open62541` passes to `open62541-env`. |
| `OPEN62541_VERSION` | `1.5.10` | open62541 release that the server is built against. |
| `OPEN62541_TAG` | `tags/v1.5.10` | Git tag of that release. |
| `MODEL` | `s7-1500-composite` | Directory below `models` that the targets `run`, `nodeset`, and `certificate` use. |
| `MODEL_PATH` | `models/$(MODEL)` | Directory of the model. |
| `MODEL_CONFIG` | `$(MODEL_PATH)/server.json5` | Server configuration file of the model. |
| `MODEL_NODESETS` | the Device Integration (DI) NodeSet and `$(MODEL_PATH)/$(MODEL).NodeSet2.xml` | NodeSet2 files that the server loads, in this order. The order fixes the namespace indices. |
| `CC` | `cc` | C compiler. |
| `MODEL_SIMULATION` | `models/<MODEL>/simulation.conf` | Simulation file of the target `run`. A relative path is read from the model directory, so give an absolute path. An empty value runs the server without a simulation file. |
| `CERT_KEY_BITS` | `2048` | RSA (Rivest-Shamir-Adleman) key size of the server certificate in bits. |
| `CERT_DAYS` | `3650` | Validity of the server certificate in days. |
| `UA_NODESET_PATH` | `$(OPEN62541_ENV_PATH)/open62541-src/deps/ua-nodeset` | Directory of the OPC Foundation NodeSet2 files. Give an absolute path, because `make run` starts the server from the model directory. |
| `EPICS_TREE` | empty | EPICS (Experimental Physics and Industrial Control System) distribution tree for the test of an IOC (input output controller). An empty value skips that test. |
| `BOOK_PAGE` | empty | Page of the book, relative to `docs/src`, that the target `book-check` runs. An empty value runs every page. |
| `APPNAME` | `opcua-server-sim` | Name of the server program. |

## Local settings files

Make reads two optional files after `configure/CONFIG_SITE`: `../CONFIG_SITE.local` and `configure/CONFIG_SITE.local`. The file `configure/RELEASE` reads `../RELEASE.local` and `configure/RELEASE.local` in the same way. The variables `OPEN62541_NAMESPACE_ZERO`, `OPEN62541_ALARMS_CONDITIONS`, `OPEN62541_VERSION`, and `OPEN62541_TAG` take effect for `make open62541` only on the command line, because the files expand `OPEN62541_CMAKE_OPTIONS` and `OPEN62541_TAG` before they read the local files. Git ignores the files `configure/*.local`.
