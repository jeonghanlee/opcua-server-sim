# Run the tests

Use `make test` to check the server, probe, and model tools. Add an EPICS installation when you want to test the IOC connection as well.

## Prerequisites

- Set `<open62541_install_path>` and `<ua_nodeset_path>` as described in [Run the simulator](run.md).
- Have `openssl` and `prove` available. Run the commands from the checkout root.

1. Run the simulator tests. The target builds the server and probe and prepares the server certificate. This command skips the IOC test.

   <!-- doc-check: prove-ok=t/server.t -->
   ```bash
   make test OPEN62541_PATH="<open62541_install_path>" UA_NODESET_PATH="<ua_nodeset_path>" EPICS_TREE=
   ```

2. Optional: To include the IOC test, use an EPICS distribution with `iocsh.bash` and the `opcua` module. For `<epics_path>`, use the value of `EPICS_PATH` after sourcing `setEpicsEnv.bash`.

   <!-- doc-check: prove-ok=t/server.t,t/ioc.t -->
   ```bash
   make test OPEN62541_PATH="<open62541_install_path>" UA_NODESET_PATH="<ua_nodeset_path>" EPICS_TREE="<epics_path>"
   ```

## Verification

Look for `Result: PASS` and check that the `t/server.t` line ends in `ok`. If the server test is skipped, check that `<ua_nodeset_path>/DI/Opc.Ua.Di.NodeSet2.xml` exists and read the skip reason. If you included the IOC test, also check that the `t/ioc.t` line ends in `ok`.

To check the NodeSet generator by itself, run its test directly. It also ends with `Result: PASS` on success.

```bash
prove t/simatic-nodeset.t
```
