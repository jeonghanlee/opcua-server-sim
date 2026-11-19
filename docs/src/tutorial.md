# Explore the simulator with the probe

Read and write a tag, call a method, and see what changes when the simulated S7-1500 moves between RUN and STOP.

## Prerequisites

- [Install open62541](procedures/open62541.md). Use its installation directory for `<open62541_install_path>`.
- Set `<ua_nodeset_path>` as described in [Run the simulator](procedures/run.md).
- Open two terminals at the checkout root. Have `perl` and `openssl` available and keep TCP port 4840 free.

## Start the demo

1. In terminal one, build and start the server. Leave it running when it opens port 4840.

   <!-- doc-check: background ready=Creating listen socket.*port 4840 -->
   ```bash
   make run OPEN62541_PATH="<open62541_install_path>" UA_NODESET_PATH="<ua_nodeset_path>"
   ```

2. In terminal two, build the probe. Run the remaining probe commands in this terminal.

   ```bash
   make probe OPEN62541_PATH="<open62541_install_path>"
   ```

## Read, write, and call

3. Browse `DataStatic` to find its tags and node IDs. Look for `myInt` in the list.

   ```bash
   build/opcua-probe opc.tcp://127.0.0.1:4840 browse 'ns=3;s="DataStatic"'
   ```

4. Read `myInt`. The probe returns its start value.

   ```bash
   build/opcua-probe opc.tcp://127.0.0.1:4840 read 'ns=3;s="DataStatic"."myInt"'
   ```

   Expected output.

   ```
   Good 42
   ```

5. Write `7` to `"Data_block_2"."Static_1"` as a signed 16-bit integer.

   ```bash
   build/opcua-probe opc.tcp://127.0.0.1:4840 write 'ns=3;s="Data_block_2"."Static_1"' int16 7
   ```

   Expected output.

   ```
   Good
   ```

6. Read back `Static_1` to confirm the write.

   ```bash
   build/opcua-probe opc.tcp://127.0.0.1:4840 read 'ns=3;s="Data_block_2"."Static_1"'
   ```

   Expected output.

   ```
   Good 7
   ```

7. Call the `OpenDoor_DB` method with one integer argument. It returns the same value.

   ```bash
   build/opcua-probe opc.tcp://127.0.0.1:4840 call 'ns=3;s="OpenDoor_DB"' 'ns=3;s="OpenDoor_DB".Method' int16:7
   ```

   Expected output.

   ```
   Good
   out 7
   ```

## Try STOP and RUN

8. Write `false` to `Simulator.Run` to put the simulated CPU in STOP.

   ```bash
   build/opcua-probe opc.tcp://127.0.0.1:4840 write 'ns=4;s=Simulator.Run' bool false
   ```

   The write returns `Good`. Read the operating mode to confirm STOP.

   ```bash
   build/opcua-probe opc.tcp://127.0.0.1:4840 read 'ns=3;s=OperatingMode'
   ```

   Expected output.

   ```
   Good 4
   ```

9. Call the method again. In STOP the server rejects method calls.

   ```bash
   build/opcua-probe opc.tcp://127.0.0.1:4840 call 'ns=3;s="OpenDoor_DB"' 'ns=3;s="OpenDoor_DB".Method' int16:7
   ```

   Expected output.

   ```
   BadInvalidState
   ```

10. Write `true` to `Simulator.Run` to return to RUN.

    ```bash
    build/opcua-probe opc.tcp://127.0.0.1:4840 write 'ns=4;s=Simulator.Run' bool true
    ```

    The write returns `Good`. Read `Static_1` again to confirm the restart restored its start value.

    ```bash
    build/opcua-probe opc.tcp://127.0.0.1:4840 read 'ns=3;s="Data_block_2"."Static_1"'
    ```

    Expected output.

    ```
    Good 0
    ```

Stop the server with Ctrl+C in terminal one. To read the model through Channel Access, follow [Run an IOC against the simulator](procedures/ioc.md).
