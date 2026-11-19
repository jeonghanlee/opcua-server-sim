# Sources of the S7-1500 model data

## Scope

Use these tables to trace the composite model and simulated server behavior to their sources. For a list of nodes, see [Contents of the composite model](src/reference/model-contents.md). To run the simulator, start with the [Quick Start](QUICKSTART.md).

## Namespaces and names

| Data | Source |
| --- | --- |
| Namespace indices 0 to 3 are fixed; URIs of indices 0, 2, and 3 | [1, pp. 188-189] |
| Namespace URI `http://www.siemens.com/simatic-s7-opcua` is reserved for the standard SIMATIC server interface | [1, p. 316] |
| Application name `SIMATIC.S7-1500.OPC-UA.Application:` + CPU name up to STEP 7 V20; CPU name alone as of STEP 7 V21 and firmware V4.1 | [1, p. 261] |
| Server URI at namespace index 1; `urn:SIMATIC:` + application name as of STEP 7 V21 | [1, p. 262] |
| Server URI `urn:SIMATIC.S7-1500.OPC-UA.Application:PLC_1` at namespace index 1 | [1, p. 496], [2, slide 25] |
| Default port 4840, configurable from 1024 to 49151 | [1, p. 265] |

## PLC object

| Data | Source |
| --- | --- |
| NodeId `ns=3;s=PLC`, browse name `3:PLC_1`, type definition `ns=3;i=1002` | [3, p. 28] |
| PLC object below `Objects` and below `DeviceSet` | [1, Fig. 11-4], [1, Fig. 11-15], [2, slide 23] |
| Children of the PLC object: seven areas and the device properties | [1, Fig. 11-13], [3, p. 28] |
| Browse name namespace of the device properties: `2:` for the DI properties, `3:` for `EngineeringRevision` and `OperatingMode` | [1, Fig. 11-4], [1, Fig. 11-15] |
| Type `SimaticDeviceType`, subtype of the DI `DeviceType`, with components `i=5059` to `i=5065` and properties `i=6070` to `i=6072` | [4], [5] |
| Property declaration `ns=3;i=6070` with a display name and a description; the figure shows four languages, the model carries English only | [1, Fig. 11-85] |
| Type `ns=2;i=1005` of the areas; the descriptions of the PLC object, the areas, and the device properties are text of this project | [4], [5] |
| `Icon` properties `ns=3;i=5201` to `ns=3;i=5204` | [6] |
| `Icon` data type `ImagePNG`, read only | [1, Fig. 11-84] |
| `OperatingMode`: data type `SimaticOperatingState`, value `8 (Run)` | [1, Fig. 11-15] |
| Operating state values 1 to 31 of the table of [1], and the values 0, 11, 12, 16 (`NotSupported`, `LinkUp`, `Update`, `CiR`) of the export in [4] | [1, pp. 498-499], [4] |

## Data types

| Data | Source |
| --- | --- |
| Mapping of SIMATIC data types to OPC UA data types | [1, Table 11-1] |
| SIMATIC node types are subtypes of OPC UA built-in types | [1, p. 305] |
| `BYTE` `ns=3;i=3001`, `STRING` `ns=3;i=3014`, `SimaticOperatingState` `ns=3;i=3063` | [4] |
| `SimaticStructures` `ns=3;i=3400`, abstract, and `SimaticStructuresType` `ns=3;i=2400` | [4], [7] |
| `SimaticSystemStructures` `ns=3;i=3500` | [8] |
| Node names of a structure: `DT_`, `VT_`, `TE_`, `TD_` prefixes | [4], [7] |
| Type name `"block"."member"` of an anonymous structure | [4] |
| Type dictionary `3:SimaticStructures`, `ns=3;i=6001`, below the OPC Binary type system | [9], [4] |
| Dictionary fields of an array: a `<name>_Size` length field and `LengthField` | [9], [4] |
| Structures are sent as ExtensionObject with the data type NodeId in front | [1, p. 241] |
| `DTL` members `YEAR` to `NANOSECOND` and their types | [3, pp. 49-50] |
| Encoding NodeId `TE_DTL` of `DTL` | [10] |
| System data types `DTL`, `IEC_Counter`, `IEC_TIMER` are derived from structures | [1, p. 256] |

## Tags

| Data | Source |
| --- | --- |
| Tag identifier: the tag name in quotation marks, components separated by a dot | [1, p. 185] |
| Memory tags `"StartTimer"`, `TimerExpired`, `TimerExpiredMerker`, `MyValue` below `Memory` | [1, Fig. 11-4] |
| Array data block `"MyDB"."THIS"` with elements `0` to `9`, index range `0:9` | [1, p. 185], [1, Fig. 11-4] |
| Tag declaration in an exported file: `ns=3;s="Data_block_2"."Static_1"`, `DataType="INT"`, `AccessLevel="3"` | [1, p. 252] |
| Data blocks `DataStatic` and `DataSimulation` and their tags | [3, p. 41], [11, p. 34] |
| `DataSimulation` holds pseudo-random values; `DataStatic` holds predefined values | [3, p. 59] |
| `"DataStatic"."myUdt"` members and values, `myArrayBool`, `myArrayInt` | [3, pp. 43-50] |
| Start values `myBool` true, `myByte` 16#AB, `myWord` 16#CDEF | [3, p. 15] |
| Tag attributes: type definition `i=63`, AccessLevel 3, MinimumSamplingInterval -1, Historizing false | [3, p. 41] |
| AccessLevel values and their mapping to the STEP 7 tag settings | [1, pp. 252-254] |
| AccessLevelEx bits 8 and 9 of tags that cannot be read or written consistently | [1, pp. 254-255] |
| Array elements as separate nodes with numeric browse names | [1, Fig. 11-4], [4] |
| Data blocks and memory tags are organized by their area | [4], [5] |
| Data block `Data_block_1` with `myInt`, `myWord`, `myString`, `myBool`, `myDouble` | [12] |
| PLC type to EPICS record type mapping; 1000 items per service call | [13] |

## Methods

| Data | Source |
| --- | --- |
| A method instance is an object below `DataBlocksInstance` with a `Method` node and `Static`, `Inputs`, `Outputs` folders | [1, Fig. 11-5] |
| Method NodeId `ns=3;s="InstUaMethodAdding".Method` | [3, p. 50] |
| Parameter structures `UAMethod_InParameters` and `UAMethod_OutParameters` | [1, p. 501] |
| Data types allowed as method parameters | [1, pp. 329-330] |
| Example methods and their behavior | [3, pp. 51-52] |
| One call per method instance at a time | [1, p. 326] |
| Wrong array length in a parameter returns BadInvalidArgument | [1, p. 330] |
| Method call in STOP returns BadInvalidState | [1, p. 242] |

## Server behavior and limits

| Data | Source |
| --- | --- |
| Server stays in operation in STOP; values read and written in STOP | [1, p. 242] |
| Sessions, subscriptions, sampling and publishing intervals, monitored items per CPU class and firmware | [14] |
| Server methods, registrable nodes, server interfaces per CPU class | [2, slide 20], [15] |
| ServerCapabilities values of a CPU: 1000 nodes per browse, read, write, register nodes, and translate browse paths call; 1 node per method call; array length 131072; byte string length 131072; string length 16382; minimum sample rate 100 ms | [2, slide 34] |
| Security policies and user authentication | [1, pp. 275-281] |
| Alarms and Conditions: nodes, event types, fields, methods | [1, pp. 331-356] |
| Diagnostic nodes of the server: `ServerDiagnosticsSummary` with `CurrentSessionCount` and `SecurityRejectedSessionCount`, `SessionsDiagnosticsSummary` with `ActualSessionTimeout`, `SubscriptionDiagnosticsArray`; open62541 provides them and `t/server.t` reads them | [1, pp. 357-358] |
| Continuation point counts `MaxBrowseContinuationPoints`, `MaxHistoryContinuationPoints`, `MaxQueryContinuationPoints` 5; the server keeps its own limit | [2, slide 34] |
| 30 subscriptions over all sessions, 50 per session, 10,000 monitored items per subscription; `BadTooManySubscriptions` and `BadTooManyMonitoredItems` beyond them | [14] |
| Limits of the CPU classes 1511 to 1513, 1515 and 1516, and 1517 and 1518: sessions, smallest sampling and publishing interval, and the alarm queue sizes | [14], [2, slide 20] |
| Alarm queue: an alarm beyond `MaxAlarmsInQueue` is outstanding; the overload alarm is active from the maximum until no alarm is outstanding and the count is below the maximum minus `OverloadHysteresis` | [1, p. 355] |

## Documented behavior without a counterpart in the server

| Data | Source | Status |
| --- | --- | --- |
| Sampling interval -1 follows the publishing interval; 0 requests the smallest interval | [1, p. 192] | Not checked; the behavior is that of open62541 |
| Queue overflow discards the oldest values | [1, p. 269] | Not checked; the behavior is that of open62541 |
| Status GoodOverload when sampling is not finished in time | [1, pp. 365-366] | Not built |
| Registered nodes above the configured maximum keep their string NodeId | [1, p. 266] | Not built |
| A subscription created with up to 1000 monitored items cannot grow past 1000; `BadOutOfMemory` beyond the quantity framework of the server | [14] | Not built; the library takes one value per limit and returns `BadOutOfMemory` only when an allocation fails |

## Model s7-1500-composite

The model `models/s7-1500-composite` holds everything the sections above list and
the data of this section. Rows marked "choice of this model" have no source:
the documents name the item but a screenshot cuts the detail off, or do not
print it.

| Data | Source |
| --- | --- |
| Numeric NodeIds `ns=3;i=3001` to `ns=3;i=3014` of `BYTE`, `WORD`, `DWORD`, `LWORD`, `S5TIME`, `TIME`, `LTIME`, `DATE`, `TOD`, `LTOD`, `DT`, `CHAR`, `WCHAR`, `STRING` | [16], [17], [18] |
| `TIMER` `ns=3;i=3015`, `COUNTER` `ns=3;i=3016`; `SimaticSystemStructures` is a subtype of `Structure` | [16] |
| `DT` is a subtype of `Byte`; a `DT` tag is an array of eight bytes | [1, Table 11-1], [19] |
| Members of a `DTL` tag are read-only; the structure as a whole is writable | [1, Table 11-1] |
| `SimaticBlockType` `ns=3;i=1003`; reference types `HasInOutVar`, `HasInputVar`, `HasOutputVar`, `HasLocalVar`, `HasBaseObject` `ns=3;i=4002` to `ns=3;i=4006`; folders `InOuts` `i=5067`, `Inputs` `i=5079`, `Outputs` `i=5026`, `Static` `i=5066` | [16], [20] |
| Instance data block: object type `OT_"<function block>"`, folder NodeId `"<block>".Static`, tag NodeId `"<block>"."<tag>"` without the folder name, `HasLocalVar` reference | [20], [21] |
| Data block `IEC_Timer_0_DB` with the Variables `"IEC_Timer_0_DB".PT`, `.ET`, `.IN`, `.Q`; `ET` and `Q` read-only | [20] |
| Array of structures: element nodes `[n]` of the structure type, with member nodes below each element; type definition `i=62` of a structure array | [4] |
| Data block `globalDB` with `udtDemo`, `udtDemo2`, and a structure without a type name | [4] |
| `V_"<type>"."<member>"` Variables below the VariableType of a structure | [4], [19] |
| Clock memory tags `Clock_10Hz` to `Clock_0.5Hz` and `Clock_Byte` below `Memory` | [4], [21] |
| `DataStatic`: `myBool` true, `myInt` 42, values of `myArrayBool` and `myArrayInt`, members and values of `myUdt` | [3, pp. 30, 42-50] |
| `DataSimulation`: tags `myBool` to `myUInt`, `myArray` with elements of type Byte, filled with pseudo-random values in every cycle | [3, pp. 41, 46, 59] |
| Lengths 22, 38, and 32 of `myArrayBool`, `myArrayInt`, `myArray`; type name `udtData` of `myUdt`; tag `myReal`; length 10 of `udtArrayString`; value `CompositePLC` of `udtString` | choice of this model |
| Method NodeId `"InstUaMethodAdding".Method`; arguments `number1`, `number2`, `result` of type Float; the method adds its inputs | [3, pp. 50-52, 59] |
| Method instances `InstMethodEcho`, `InstMethodSort`, `InstMethodStoreTime`, `InstMethodSequence`, their function blocks, the arguments `values`, `sorted`, and `time`, and the tags `cancel` and `fault` | choice of this model |
| The behaviors of the four methods: return the inputs, sort an array of Int, take a time value, run a timed sequence that refuses a second call; argument names `inBool` to `inWString`; the duration of the sequence | choice of this model |
| `OpenDoor_DB` with `Method`, `InputArguments`, `OutputArguments`, `Number`, and `Result` of type Int | [1, Fig. 11-5], [1, Fig. 11-80] |
| `Data_for_OPC_UA_Clients` (`NewProduct`, `ProductNumber`, `Temperature`, read-only) and `Data_from_OPC_UA_Clients` (`ProductionEnabled`) | [1, pp. 374-386] |
| Length 10 of `Temperature`; function block name `OpenDoor`; the method returns its input | choice of this model |
| A method call while the CPU is in STOP returns `BadInvalidState` | [1, p. 242] |
| Alarm objects below `Server`: `SimaticAlarmsAndConditions`, `Overloads`, `ProgramAlarms` with `Graph`, `ProcessDiagnostics`, `UserProgram`, and `SystemDiagnostics`, with their properties | [1, p. 356] |
| Event notifiers `Server`, `SimaticAlarmsAndConditions`, `ProcessDiagnostics`, `SystemDiagnostics`, `UserProgram` | [1, p. 335] |
| `SimaticEventType` below `BaseEventType`, `SimaticAlarmConditionType` below `AlarmConditionType`, and their fields | [1, pp. 336-340] |
| NodeIds `ns=3;i=1804` and `ns=3;i=1805` of the two types; union `SimaticAssociatedAlarmValue` `ns=3;i=1809` with encoding `ns=3;i=1810` and its 13 members | [22] |
| Severity of an alarm priority: 600 for priority 10, 300 for priority 4, 720 for priority 12 | [1, p. 337] |
| Example alarms `Program_Alarm` (information only, text `myText`), `Program_Alarm_1` (acknowledgment), `Program_Alarm_2` (with a state) | [1, p. 332] |
| Acknowledgment with the method `i=9111` on the ConditionId | [1, pp. 350-351] |
| Alarm queue sizes 200 and 100 of a CPU 1515 or 1516; hysteresis 3 | [2, slide 20], [1, p. 356] |
| NodeIds of the alarm objects and of the type properties; data type UInt32 of the queue properties; data block `AlarmTriggers`; `EventNotifier` also on `ProgramAlarms` and `Graph` | choice of this model |
| Values of the identity properties of the PLC object: `DeviceManual`, `DeviceRevision`, `HardwareRevision`, `SoftwareRevision`, `EngineeringRevision`, `OrderNumber`, `SerialNumber` | choice of this model |
| Security policies None, Basic128Rsa15, Basic256, Basic256Sha256, Aes128_Sha256_RsaOaep, Aes256_Sha256_RsaPss, each secured policy with Sign and SignAndEncrypt | [1, p. 275] |
| Guest access and one user account | [3, pp. 14, 59] |
| Certificate: RSA 2048 bits, SHA-256, application URI as subject alternative name | [2, slide 62], [3, p. 40] |
| Product URI `https://www.siemens.com/s7-1500` of a CPU; the model reports the address of this repository instead | [21] |

The numeric NodeIds of [16] come from a browse of an S7-1200; [17] is client
code that maps the same numbers for an S7-1500, and [18] reproduces a Siemens
FAQ table. The NodeIds of [22] are the ones a user passes to a client
library in a comment of Sep. 10, 2022, against an S7-1500 with firmware V2.9.
The export [20] is from STEP 7 V16 and the export [19] from STEP 7 V19.

## Documents without data for the standard interface

The SiOME application example shows mapped PLC tag notation for user-defined server interfaces [23].

## Software

| Software | Use |
| --- | --- |
| open62541 [24] | Server stack |
| nodesetLoader [25] | Loading NodeSet2 XML files at server start |
| UA-Nodeset [26] | `DI/Opc.Ua.Di.NodeSet2.xml`, the model at namespace index 2 |

## References

[1] Siemens AG, Nuremberg, Germany. *SIMATIC S7-1500, ET 200MP, ET 200SP, ET 200BL, ET 200AL, ET 200pro, ET 200eco PN, ET 200clean Communication Function Manual*, 11/2025 ed. (2025). Accessed: Nov. 11, 2026. [Online]. Available: https://cache.industry.siemens.com/dl/files/925/59192925/att_901175/v4/s71500_communication_function_manual_en-US_en-US.pdf

[2] Siemens s.r.o. (2022). *Simatic S7-1500 OPC UA server* [Online]. Available: https://assets.new.siemens.com/siemens/assets/api/uuid:f38282b2-005c-47d6-822e-5cf2e6dc0142/simatic-plc-opc-ua-server-public.pdf

[3] "OPC UA .NET client for the SIMATIC S7-1500 OPC UA server," Siemens AG, Entry ID 109737901, V1.5, Sep. 2022. Accessed: Nov. 11, 2026. [Online]. Available: https://cache.industry.siemens.com/dl/files/901/109737901/att_1116717/v2/109737901_OPC_UA_Client_S7-1500_DOKU_V1_5_en.pdf

[4] mtenberge. "XML Nodeset compiler: generated code emits various errors, array nodes are not created." GitHub. Accessed: Nov. 11, 2026. [Online.] Available: https://github.com/open62541/open62541/issues/2119

[5] gauss345. "xmlimporter loops infinitely when sorting nodes by parentid, when parentid is not found." GitHub. Accessed: Nov. 11, 2026. [Online.] Available: https://github.com/FreeOpcUa/opcua-asyncio/issues/1061

[6] EirikAlbrektsen. "Client browsing does not find all nodes (Simatic PLC)." GitHub. Accessed: Nov. 11, 2026. [Online.] Available: https://github.com/open62541/open62541/issues/3081

[7] andreas-ibm. "Nested VariableType nodes." GitHub. Accessed: Nov. 11, 2026. [Online.] Available: https://github.com/open62541/open62541/issues/1414

[8] jadevicpavel. "Error: Cannot find dataType Definition ! with nodeId =ns=3;i=3400." GitHub. Accessed: Nov. 11, 2026. [Online.] Available: https://github.com/mikakaraila/node-red-contrib-opcua/issues/460

[9] itrukw. "get_child - BadNoMatch issue accessing an array in a Siemens OPC UA Server." GitHub. Accessed: Nov. 11, 2026. [Online.] Available: https://github.com/FreeOpcUa/python-opcua/issues/474

[10] clemensg. "Problem with a client reading custom datatypes." GitHub. Accessed: Nov. 11, 2026. [Online.] Available: https://github.com/open62541/open62541/issues/4222

[11] "OPC UA .NET client for the SIMATIC S7-1500 OPC UA server," Siemens AG, Entry ID 109737901, V1.0, Oct. 2016. Accessed: Nov. 11, 2026. [Online]. Available: https://cache.industry.siemens.com/dl/files/901/109737901/att_898965/v3/109737901_OPC_UA_Client_S7-1500_DOKU_V10_en.pdf

[12] R. Lange and D. Zimoch. *EPICS Device Support for OPC UA*. (Nov. 17, 2025). GitHub. (v0.11.2). Accessed: Nov. 11, 2026. [Online]. Available: https://github.com/epics-modules/opcua

[13] "Configuring the OPC UA Server on a Siemens S7-1500 Series PLC." EPICS OPC UA Device Support documentation. Accessed: Nov. 11, 2026. [Online.] Available: https://epics-modules.github.io/opcua/how-to/plc_configuration.html

[14] "TIA Portal OPC UA system limits for the S7-1500/S7-1200 CPUs," Siemens AG, Entry ID 109755846, V1.0, Feb. 2024. Accessed: Nov. 11, 2026. [Online]. Available: https://cache.industry.siemens.com/dl/files/846/109755846/att_1163306/v4/109755846_TIA_Portal_OPC_UA_system_limits.pdf

[15] Siemens AG. (2020). *OPC UA for S7-1500 and S7-1200* [Online]. Available: https://assets.new.siemens.com/siemens/assets/api/uuid:d01f17aa-551e-4f68-9c55-93c6689c00ce/siemens-opc-ua-webinar-27aug2020.pdf

[16] vmalani27. "opcua_browse_output.txt." GitHub. Accessed: Nov. 11, 2026. [Online.] Available: https://github.com/vmalani27/bvm_control_system/blob/HEAD/opcua_browse_output.txt

[17] philipp2604. "S7UaClient.cs." GitHub. Accessed: Nov. 11, 2026. [Online.] Available: https://github.com/philipp2604/S7UaLib/blob/HEAD/src/S7UaLib.Infrastructure/Ua/Client/S7UaClient.cs

[18] D. Madeo, "F.A.Q. - Quali ID del nodo sono disponibili e le descrizioni dei tipi di dati nel Server OPC UA di PLC S7-1200 / S7-1500?," *Domenico Madeo*, Mar. 13, 2024. [Online]. Available: https://domenicomadeo.com/f-a-q-quali-id-del-nodo-sono-disponibili-e-le-descrizioni-dei-tipi-di-dati-nel-server-opc-ua-di-plc-s7-1200-s7-1500/

[19] thomasglauser. "test_import.xml." GitHub. Accessed: Nov. 11, 2026. [Online.] Available: https://github.com/thomasglauser/TIA-Portal-OPC-UA-Export-to-JSON/blob/HEAD/test/test_import.xml

[20] alabuga-web. "PLC_2.OPCUA.xml." GitHub. Accessed: Nov. 11, 2026. [Online.] Available: https://github.com/alabuga-web/expo-dashboard/blob/HEAD/back/%D0%92%D1%8B%D1%81%D1%82%D0%B0%D0%B2%D0%BA%D0%B0%20%D0%B4%D0%B5%D0%BC%D0%BE.PLC_2.OPCUA.xml

[21] FlowTheTensor. "UAExpertExport." GitHub. Accessed: Nov. 11, 2026. [Online.] Available: https://github.com/FlowTheTensor/Datenkrake/tree/HEAD/UAExpertExport

[22] "Usage of ExtensionObjects." GitHub. Accessed: Nov. 11, 2026. [Online.] Available: https://github.com/FreeOpcUa/opcua-asyncio/discussions/839

[23] "Siemens OPC UA Modeling Editor zur Umsetzung von OPC UA Companion Spezifikationen," Siemens AG, Entry ID 109755133, V1.0, Feb. 2018. Accessed: Nov. 11, 2026. [Online]. Available: https://cache.industry.siemens.com/dl/files/133/109755133/att_942160/v4/109755133_SiOME_DOC_V10_de.pdf

[24] *open62541*. (Oct. 30, 2026). GitHub. (v1.5.10). Accessed: Nov. 11, 2026. [Online]. Available: https://github.com/open62541/open62541

[25] *nodesetLoader*. (Feb. 20, 2026). GitHub. (commit bcfe420). Accessed: Nov. 11, 2026. [Online]. Available: https://github.com/open62541/nodesetLoader

[26] *UA-Nodeset*. (Mar. 8, 2026). GitHub. (commit 257db9a). OPC Foundation. Accessed: Nov. 11, 2026. [Online]. Available: https://github.com/OPCFoundation/UA-Nodeset
