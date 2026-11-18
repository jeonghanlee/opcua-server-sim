# Run the demo server

**Document:** opcua-server-sim quick start

**Revision:** a733dc7

**Date:** 2026-11-18

**Prepared by:** Jeong Han Lee

**Applies to:** the demo server of opcua-server-sim.

This page builds the simulator of a Siemens S7-1500 OPC UA (Open Platform Communications Unified Architecture) server, starts it, and reads one value with the probe, its client. The tutorial in the repository, `docs/src/tutorial.md`, explains each step.

## Prerequisites

- A Linux host with network access and TCP (Transmission Control Protocol) port 4840 free.
- A directory that you can write to for the open62541 installation, which this page names `<open62541_install_path>`.

**Step 1.** Install the build tools (Debian names):

```bash
sudo apt install build-essential git pkg-config cmake python3 perl openssl
sudo apt install libssl-dev libxml2-dev
```

**Step 2.** Clone the repository, and change to its directory, which this page calls the repository root:

```bash
git clone https://github.com/jeonghanlee/opcua-server-sim
cd opcua-server-sim
```

**Step 3.** In the repository root, clone the branch `1.5` of open62541-env next to the repository:

```bash
git clone -b 1.5 https://github.com/jeonghanlee/open62541-env ../open62541-env
```

**Step 4.** Download, build, and install open62541 1.5.10. The command takes several minutes:

```bash
make open62541 OPEN62541_PATH=<open62541_install_path>
```

**Step 5.** Build the server and the probe:

```bash
make build OPEN62541_PATH=<open62541_install_path>
make probe OPEN62541_PATH=<open62541_install_path>
```

**Step 6.** In the first terminal, start the server. It runs until you press Ctrl+C. `<ua_nodeset_path>` is the absolute path of `../open62541-env/open62541-src/deps/ua-nodeset`:

```bash
make run OPEN62541_PATH=<open62541_install_path> UA_NODESET_PATH=<ua_nodeset_path>
```

## Verification

In a second terminal, in the repository root, read the operating state of the simulated CPU (central processing unit). The probe prints the status name and the value 8, which means RUN:

```bash
build/opcua-probe opc.tcp://127.0.0.1:4840 read 'ns=3;s=OperatingMode'
```

```
Good 8
```
