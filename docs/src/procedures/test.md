# Run the tests

The target `make test` builds the server and the probe, creates the certificate, and runs the Perl tests of the directory `t` with `prove`. This procedure runs the tests, and optionally the test that connects an EPICS (Experimental Physics and Industrial Control System) IOC (input output controller) to the server.

## Prerequisites

- The prerequisites of [Build the server and the probe](build.md), and the path of the installation of open62541, which this page names `<open62541_install_path>`.
- The directory of the OPC Foundation NodeSet2 files, which this page names `<ua_nodeset_path>`. [Run the simulator](run.md) says where to find it.
- `openssl` and `prove` in `PATH`.
- For the optional step, an EPICS distribution tree that holds `base/bin/<arch>/iocsh.bash` and the opcua device support module, which is the EPICS software that connects records to OPC UA (Open Platform Communications Unified Architecture) servers. This page names its root `<epics_tree>`.

1. In the repository root, run the tests. The test of the server starts the server and takes about two minutes; the command is piped to `tail` so that only the last line of the output is shown:

   ```bash
   make test OPEN62541_PATH=<open62541_install_path> UA_NODESET_PATH=<ua_nodeset_path> |& tail -n 1
   ```

   `<open62541_install_path>` is the installation path of open62541. `<ua_nodeset_path>` is the directory of the OPC Foundation NodeSet2 files.

   The last line states the result of all tests:

   ```
   Result: PASS
   ```

2. Optional: to run the IOC test as well, name the EPICS tree in the variable `EPICS_TREE`:

   ```bash
   make test OPEN62541_PATH=<open62541_install_path> UA_NODESET_PATH=<ua_nodeset_path> EPICS_TREE=<epics_tree> |& tail -n 1
   ```

   `<epics_tree>` is the root of the EPICS distribution tree.

   The last line is again:

   ```
   Result: PASS
   ```

## Verification

Run the test of the NodeSet generator alone, which needs only Perl. The command shows the last line of the output:

```bash
prove t/simatic-nodeset.t | tail -n 1
```

The command prints:

```
Result: PASS
```

Without the variable `EPICS_TREE`, the test `t/ioc.t` is skipped and the run ends with `Result: PASS`.
