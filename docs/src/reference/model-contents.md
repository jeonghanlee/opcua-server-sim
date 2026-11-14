# Contents of the composite model

The composite model `s7-1500-composite` is the OPC UA (Open Platform Communications Unified Architecture) information model that the simulator serves by default. The model combines the data blocks of several Siemens examples and exports in one namespace. This page lists the namespaces, the data blocks, the memory tags, the structures, the methods, and the behavior that the shipped simulation file gives to them.

## Namespaces of the server

The load order of the NodeSet files fixes the indices 0 to 3, which the server logs when it starts. Index 4 exists only when the simulation file has an `operating-mode` line: it holds the Boolean `Simulator.Run`, which the server adds.

| Index | Namespace URI (uniform resource identifier) |
| --- | --- |
| 0 | `http://opcfoundation.org/UA/` |
| 1 | `urn:SIMATIC.S7-1500.OPC-UA.Application:PLC_1` |
| 2 | `http://opcfoundation.org/UA/DI/` |
| 3 | `http://www.siemens.com/simatic-s7-opcua` |
| 4 | `urn:opcua-server-sim:control` |

The PLC (programmable logic controller) object is `ns=3;s=PLC` with the browse name `3:PLC_1`. The tags of the model are in namespace 3.

## Global data blocks

A tag is the node `ns=3;s="<block>"."<tag>"`.

| Block | Tags | Origin |
| --- | --- | --- |
| `DataStatic` | `myBool`, `myByte`, `myWord`, `myDword`, `myInt`, `myUInt`, `myReal`, `myArrayBool` (22 elements), `myArrayInt` (38 elements), `myUdt` | Siemens client example, predefined values. |
| `DataSimulation` | `myBool`, `myByte`, `myWord`, `myDword`, `myInt`, `myUInt`, `myReal`, `myArray` (32 bytes) | Siemens client example, values that change over time. |
| `DataTypes` | One tag of each of 30 SIMATIC data types, from `myBool` to `myDtl` | Every data type that the server maps. |
| `MyDB` | `THIS` (array of 10 `Int`) | Array data block. |
| `Data_block_1` | `myInt`, `myWord`, `myString`, `myBool`, `myDouble` | S7-1500 example database of the EPICS (Experimental Physics and Industrial Control System) opcua module. |
| `Data_block_2` | `Static_1` | Export example of the function manual. |
| `Data_for_OPC_UA_Clients` | `NewProduct`, `ProductNumber`, `Temperature` (10 `Real` values) | Production line example, read only for clients. |
| `Data_from_OPC_UA_Clients` | `ProductionEnabled` | Production line example, written by clients. |
| `IEC_Timer_0_DB` | `PT`, `ET`, `IN`, `Q` | IEC (International Electrotechnical Commission) timer data block. |
| `AlarmTriggers` | `Program_Alarm`, `Program_Alarm_1`, `Program_Alarm_2`, `Program_Alarm_3`, `System_Alarm`, `Overload_Program`, `Overload_System` | Boolean triggers of the alarms. The queue logic writes `Overload_Program` and `Overload_System` in every step, so a client cannot set them. |
| `globalDB` | `singleInt`, `arrayOfBools`, `UntypedStruct`, `instanceOfUdt`, `arrayOfUdts` | STEP 7 export with arrays and nested structures. |

The member NodeIds of `IEC_Timer_0_DB` are written without quotation marks: `ns=3;s="IEC_Timer_0_DB".IN`.

## Instance data blocks

Each instance data block belongs to a function block and holds one method.

| Block | Function block | Method behavior in the shipped simulation file |
| --- | --- | --- |
| `InstUaMethodAdding` | `UaMethodAdding` | `sum`: adds the two `Real` inputs. |
| `InstMethodEcho` | `MethodEcho` | `echo`: returns each input unchanged. |
| `InstMethodSort` | `MethodSort` | `sort`: returns the array of 10 `Int` in ascending order. |
| `InstMethodStoreTime` | `MethodStoreTime` | `accept`: takes an `LDT` value and returns nothing. |
| `InstMethodSequence` | `MethodSequence` | `accept` with `busy=3000`: refuses another call for 3000 ms. |
| `OpenDoor_DB` | `OpenDoor` | `echo`: returns the `Int` input as the result. |

## Memory tags of the model

The memory tags are the nodes `ns=3;s="<name>"`: `StartTimer`, `TimerExpired`, `TimerExpiredMerker`, `MyValue`, `Clock_0.5Hz`, `Clock_0.625Hz`, `Clock_1.25Hz`, `Clock_2.5Hz`, `Clock_10Hz`, `Clock_1Hz`, `Clock_2Hz`, `Clock_5Hz`, and `Clock_Byte`.

## Structures of the model

The model defines the structure types `DTL`, `udtDemo2`, `udtDemo`, `udtData`, and `"globalDB"."UntypedStruct"`. It defines one structure type for the input and one for the output arguments of each method that has them, named `"<block>"."UAMethod_InParameters"` and `"<block>"."UAMethod_OutParameters"`.

## Behavior of the shipped simulation file

The file `models/s7-1500-composite/simulation.conf` gives the model its behavior.

| Element | Behavior |
| --- | --- |
| Simulation step | Every 50 ms. |
| Operating state | `ns=3;s=OperatingMode`: 8 in RUN and 4 in STOP. |
| `DataSimulation` tags | Random values every 1000 ms: the whole range of the data type, and -1000 to 1000 for `myReal`. |
| `Data_for_OPC_UA_Clients` | `NewProduct` toggles between 0 and 1 every 5000 ms. `ProductNumber` counts from 1 to 32767 by 1 every 10000 ms. `Temperature` takes random values from 20 to 80 every 1000 ms. |
| Clock memory | The `Clock_*Hz` bits toggle at their frequency. `Clock_Byte` packs them: bit 0 is 10 Hz and bit 7 is 0.5 Hz. |
| Timers | `TimerExpired` is set 5000 ms after `StartTimer` is true. `IEC_Timer_0_DB.Q` is set after `IN` has been true for `PT`, and `ET` shows the elapsed time. |
| Alarms | `Program_Alarm` is an event of severity 300. `Program_Alarm_1`, `Program_Alarm_2`, and `Program_Alarm_3` are alarms with a state of severity 600, 720, and 600. `System_Alarm` is an alarm of severity 500 reported from `SimaticAlarmsAndConditions.SystemDiagnostics`. |
| Alarm queues | One queue for the program alarms and one for the system diagnostics alarms, each with its overload alarm of severity 900. The queue maxima are 200 and 100, and the model has three program alarms and one system alarm, so the shipped files never reach an overload. |
| CPU (central processing unit) counts | The server reports 5 browse, 5 query, and 5 history continuation points. |
| Accounts | Anonymous access is allowed. The user `simulator` has the password `composite`. |

The files `simulation-1511-1513.conf` and `simulation-1517-1518.conf` include `simulation.conf` and set the limits of the CPU classes 1511 to 1513 and 1517 to 1518.
