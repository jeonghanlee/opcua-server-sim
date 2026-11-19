# Run an IOC against the simulator

Read two simulator values through an EPICS input/output controller (IOC) using Channel Access (CA).

## Prerequisites

- Set `<open62541_install_path>` and `<ua_nodeset_path>` as described in [Run the simulator](run.md).
- Run the server, IOC, and CA client on the same host. Keep TCP port 4840 and CA port 5164 free, and have `openssl` available.
- Use an EPICS distribution with `setEpicsEnv.bash`, `iocsh.bash`, `caget`, and the `opcua` module.

If you need a distribution, install it from the checkout root.

<!-- doc-check: skip -->
```bash
bash scripts/install-epics.bash
```

Replace `<setup>` below with `work/epics/setEpicsEnv.bash` or the path to your distribution's activation script.

1. In terminal one at the checkout root, start the server and leave it running when it opens port 4840.

   <!-- doc-check: background ready=Creating listen socket.*port 4840 -->
   ```bash
   make run OPEN62541_PATH="<open62541_install_path>" UA_NODESET_PATH="<ua_nodeset_path>"
   ```

2. In terminal two at the checkout root, activate EPICS and start the IOC. Wait for `session OPC2: connected`.

   <!-- doc-check: background ready=session OPC2: connected -->
   ```bash
   source "<setup>" >/dev/null && bash scripts/run-ioc.bash
   ```

   The script prepares the client certificate and identity file in a private directory under `work/`. The IOC uses an anonymous OPC UA session and a signed and encrypted session.

## Verification

From terminal three at the checkout root, activate the same distribution and read both PVs. The CA settings direct the read to the IOC on loopback port 5164.

```bash
source "<setup>">/dev/null && EPICS_CA_ADDR_LIST=127.0.0.1:5164 EPICS_CA_AUTO_ADDR_LIST=NO caget SIM:Static:Int SIM:Mode
```

Expected output. The operating mode `8` means RUN.

```
SIM:Static:Int                 42
SIM:Mode                       8
```

Press Ctrl+C in terminal two to stop the IOC and in terminal one to stop the server. See the [demo IOC PV list](https://github.com/jeonghanlee/opcua-server-sim/blob/master/docs/QUICKSTART.md#3-demo-ioc-pv-list) for the other signals.
