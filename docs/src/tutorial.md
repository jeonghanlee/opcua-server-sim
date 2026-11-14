# Build the simulator and read a tag with the probe

In this tutorial you build the simulator and its probe client, start the server, and use the probe to read, write, and call the nodes of a simulated Siemens S7-1500 CPU (central processing unit). At the end you have seen a value, a write, a method call, and the STOP state of the CPU.

## Prerequisites

The [glossary](glossary.md) defines the terms that this page uses, such as tag, Variable, start value, and signal.

- A Linux host with `cc`, `make`, `perl`, and `openssl` in `PATH`.
- An installation of open62541 1.5.10 with the NodeSet loader, which reads NodeSet2 files, and the Alarms and Conditions support, which provides the alarm model of OPC UA (Open Platform Communications Unified Architecture). [Build the server and the probe](procedures/build.md) says how to get one. This page names its path `<open62541_install_path>`.
- The directory of the OPC Foundation NodeSet2 files, which this page names `<ua_nodeset_path>`. [Run the simulator](procedures/run.md) says where to find it.
- Two terminals in the repository root, and TCP (Transmission Control Protocol) port 4840 free on the host.

## Build and start

1. In the first terminal, build the server:

   ```bash
   make build OPEN62541_PATH=<open62541_install_path>
   ```

   `<open62541_install_path>` is the installation path of open62541.

2. Build the probe:

   ```bash
   make probe OPEN62541_PATH=<open62541_install_path>
   ```

3. List the build directory. It holds the two programs and the file `identity`:

   ```bash
   ls build
   ```

   You see:

   ```
   identity
   opcua-probe
   opcua-server-sim
   ```

4. Start the server. The command creates the server certificate when it is missing, and it runs until you stop it with Ctrl+C. Run the next steps in the second terminal:

   <!-- doc-check: background ready=simulating \d+ signals -->
   ```bash
   make run OPEN62541_PATH=<open62541_install_path> UA_NODESET_PATH=<ua_nodeset_path>
   ```

   `<ua_nodeset_path>` is the directory of the OPC Foundation NodeSet2 files.

   The server logs the namespace table. The tags of the model are in namespace 3:

   ```
   [2026-11-13 16:13:54.216 (UTC-0800)] info/application	namespace 0: http://opcfoundation.org/UA/
   [2026-11-13 16:13:54.216 (UTC-0800)] info/application	namespace 1: urn:SIMATIC.S7-1500.OPC-UA.Application:PLC_1
   [2026-11-13 16:13:54.216 (UTC-0800)] info/application	namespace 2: http://opcfoundation.org/UA/DI/
   [2026-11-13 16:13:54.216 (UTC-0800)] info/application	namespace 3: http://www.siemens.com/simatic-s7-opcua
   ```

## Read, write, and call

5. In the second terminal, read the tag `myInt` of the data block `DataStatic`. The probe prints the status name and the value:

   ```bash
   build/opcua-probe opc.tcp://127.0.0.1:4840 read 'ns=3;s="DataStatic"."myInt"'
   ```

   You see the start value of the tag:

   ```
   Good 42
   ```

6. In the second terminal, browse the data block to see its tags. Each line is a browse name and a node id:

   ```bash
   build/opcua-probe opc.tcp://127.0.0.1:4840 browse 'ns=3;s="DataStatic"'
   ```

   You see the ten tags of the block:

   ```
   myBool ns=3;s="DataStatic"."myBool"
   myByte ns=3;s="DataStatic"."myByte"
   myWord ns=3;s="DataStatic"."myWord"
   myDword ns=3;s="DataStatic"."myDword"
   myInt ns=3;s="DataStatic"."myInt"
   myUInt ns=3;s="DataStatic"."myUInt"
   myReal ns=3;s="DataStatic"."myReal"
   myArrayBool ns=3;s="DataStatic"."myArrayBool"
   myArrayInt ns=3;s="DataStatic"."myArrayInt"
   myUdt ns=3;s="DataStatic"."myUdt"
   ```

7. In the second terminal, write the value 7 to the `Int` tag `Static_1`:

   ```bash
   build/opcua-probe opc.tcp://127.0.0.1:4840 write 'ns=3;s="Data_block_2"."Static_1"' int16 7
   ```

   You see the status of the write:

   ```
   Good
   ```

8. In the second terminal, read the tag again:

   ```bash
   build/opcua-probe opc.tcp://127.0.0.1:4840 read 'ns=3;s="Data_block_2"."Static_1"'
   ```

   You see the value that you wrote:

   ```
   Good 7
   ```

9. In the second terminal, call the server method of the production line example, which returns its input. An argument is `<type>:<value>`, and the output arguments follow the status:

   ```bash
   build/opcua-probe opc.tcp://127.0.0.1:4840 call 'ns=3;s="OpenDoor_DB"' 'ns=3;s="OpenDoor_DB".Method' int16:7
   ```

   You see the status and the output argument:

   ```
   Good
   out 7
   ```

## Stop and restart the CPU

10. In the second terminal, put the simulated CPU in STOP by writing false to the Boolean `Simulator.Run`, which is in namespace 4:

    ```bash
    build/opcua-probe opc.tcp://127.0.0.1:4840 write 'ns=4;s=Simulator.Run' bool false
    ```

    You see the status of the write:

    ```
    Good
    ```

11. In the second terminal, read the operating state:

    ```bash
    build/opcua-probe opc.tcp://127.0.0.1:4840 read 'ns=3;s=OperatingMode'
    ```

    You see the value 4, which is STOP:

    ```
    Good 4
    ```

12. In the second terminal, call the method again. In STOP the server refuses method calls:

    ```bash
    build/opcua-probe opc.tcp://127.0.0.1:4840 call 'ns=3;s="OpenDoor_DB"' 'ns=3;s="OpenDoor_DB".Method' int16:7
    ```

    You see the refusal:

    ```
    BadInvalidState
    ```

13. In the second terminal, restart the CPU by writing true:

    ```bash
    build/opcua-probe opc.tcp://127.0.0.1:4840 write 'ns=4;s=Simulator.Run' bool true
    ```

    You see the status of the write:

    ```
    Good
    ```

14. In the second terminal, read the tag `Static_1` again. The restart sets the Variable, which no signal drives, to its start value:

    ```bash
    build/opcua-probe opc.tcp://127.0.0.1:4840 read 'ns=3;s="Data_block_2"."Static_1"'
    ```

    You see the start value:

    ```
    Good 0
    ```

15. Stop the server with Ctrl+C in the first terminal.

## Where to go next

- [Run an IOC against the simulator](procedures/ioc.md) reads the same tags with an EPICS (Experimental Physics and Industrial Control System) IOC (input output controller).
- [The role of a simulation file in the server](concepts/simulation-file.md) explains the changing values and the STOP state.
- [Probe client commands](reference/probe.md) lists every command of the probe.
