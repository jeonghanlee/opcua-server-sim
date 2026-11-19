# Run and verify the demo server

**Document:** opcua-server-sim quick start

**Revision:** draft

**Date:** 2026-11-19

**Prepared by:** Jeong Han Lee

**Applies to:** the demo server of opcua-server-sim.

Run the S7-1500 simulator and check it with OPC UA and EPICS.

## 1. Install and run the server

Run the server and verification commands on the same Linux host with network access. Use a writable checkout path without spaces and keep TCP port 4840 free.

Install the build dependencies for your OS. The example below uses Debian package names.

```bash
sudo apt install build-essential git pkg-config cmake python3 perl openssl libssl-dev libxml2-dev
```

For a new checkout, run these commands from the directory where you want the repository to go.

```bash
git clone https://github.com/jeonghanlee/opcua-server-sim
cd opcua-server-sim
```

From the checkout root, set the paths below. Choose one method for each step.

```bash
ua="$PWD/work/open62541-1.5.10" env_repo="$PWD/work/open62541-env-1.5"
```

**Step 1.** Install open62541 1.5.10 with the script.

```bash
bash scripts/install-open62541.bash
```

For Make, clone `open62541-env` if `$env_repo` is absent, then install.

```bash
git clone -b 1.5 https://github.com/jeonghanlee/open62541-env "$env_repo"
make open62541 OPEN62541_PATH="$ua" OPEN62541_ENV_PATH="$env_repo"
```

**Step 2.** Build the server with either command.

```bash
bash scripts/build-server.bash
make build OPEN62541_PATH="$ua"
```

**Step 3.** Start the server with Make and leave it running.

```bash
make run OPEN62541_PATH="$ua" OPEN62541_ENV_PATH="$env_repo"
```

To start the built server with the run script, prepare the certificate and NodeSet first.

```bash
make certificate nodeset
di="$env_repo/open62541-src/deps/ua-nodeset/DI/Opc.Ua.Di.NodeSet2.xml"
bash scripts/run-model.bash --di "$di" models/s7-1500-composite
```

## 2. Verify the server

### 2.1 Verify with the OPC UA client

**Step 4.** In terminal two at the checkout root, read the CPU mode with the probe.

```bash
make probe OPEN62541_PATH="$PWD/work/open62541-1.5.10"
build/opcua-probe opc.tcp://127.0.0.1:4840 read 'ns=3;s=OperatingMode'
```

**Expected output** `Good 8` (RUN).

### 2.2 Verify with the EPICS IOC

For IOC verification, the same host must be x86_64 and use an OS version listed under [supported operating systems](https://github.com/jeonghanlee/EPICS-env-distribution#supported-operating-systems). Keep Channel Access (CA) port 5164 free.

**Step 5.** In terminal two at the checkout root, install EPICS. The script selects the distribution for your OS and version.

```bash
bash scripts/install-epics.bash
```

**Step 6.** In the same terminal, activate EPICS, start the IOC, and wait for `session OPC2: connected`.

```bash
source work/epics/setEpicsEnv.bash
bash scripts/run-ioc.bash
```

**Step 7.** In terminal three at the checkout root, activate the same EPICS distribution and read both process variables.

```bash
source work/epics/setEpicsEnv.bash
export EPICS_CA_ADDR_LIST=127.0.0.1:5164 EPICS_CA_AUTO_ADDR_LIST=NO
caget SIM:Static:Int SIM:Mode
```

**Expected output**

```
SIM:Static:Int                 42
SIM:Mode                       8
```

Stop the IOC and server with Ctrl+C.

## 3. Demo IOC PV list

The demo IOC loads these 14 records from `ioc/composite.db`.

| PV | Signal |
| -------------------- | ---------------------------------------- |
| `SIM:Static:Bool` | Static Boolean value |
| `SIM:Static:Byte` | Static byte value |
| `SIM:Static:Word` | Static word value |
| `SIM:Static:Int` | Static integer value |
| `SIM:Udt` | Parent record for the `myUdt` structure |
| `SIM:Udt:Int` | Integer member of `myUdt` |
| `SIM:Udt:Year` | Year member of `myUdt` |
| `SIM:Array:Int` | Integer array |
| `SIM:Array:Elem3` | Integer array element at index 3 |
| `SIM:Clock:Byte` | Simulated clock byte |
| `SIM:Sim:Int` | Simulated integer value |
| `SIM:Run` | CPU RUN/STOP command |
| `SIM:Mode` | CPU operating mode, `8` for RUN and `4` for STOP |
| `SIM:Secure:Byte` | Static byte read through the encrypted OPC UA session |
