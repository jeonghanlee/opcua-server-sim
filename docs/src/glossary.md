# Glossary of terms used in the book

This page defines the terms that the pages of this book use, in alphabetical order. Each term appears once, with the meaning that the pages give it.

| Term | Definition |
| --- | --- |
| Alarm | An event with a state. It becomes active when its Boolean trigger becomes true and inactive when the trigger becomes false, and clients acknowledge it. A simulation file defines it with the keyword `alarm`. |
| Alarms and Conditions | The part of OPC UA that defines alarms, events, and conditions with states. The open62541 library offers it as an optional feature. |
| Application URI | The uniform resource identifier (URI) of an OPC UA (Open Platform Communications Unified Architecture) application. The URI of the server is `urn:SIMATIC.S7-1500.OPC-UA.Application:PLC_1`, at namespace index 1. |
| Associated value | A value of the union `SimaticAssociatedAlarmValue` that an alarm or event carries in one of its fields `AssociatedValue_01` to `AssociatedValue_10`. |
| BuildInfo | The Variable of the Server object that holds the product name, the manufacturer, the software version, the build number, and the build date. |
| Channel Access | The EPICS (Experimental Physics and Industrial Control System) network protocol with which a client such as `caget` reads the records of an IOC. |
| Composite model | The information model `s7-1500-composite`, which combines the data blocks of several Siemens examples in one namespace. |
| CPU | The central processing unit of an S7-1500 controller. It runs the PLC program and the OPC UA server. |
| CPU class profile | A simulation file that includes another simulation file and then sets the limits of one CPU class. |
| Data block | A named group of tags of a PLC (programmable logic controller) program. A global data block holds tags of its own. An instance data block belongs to a function block and holds a method. |
| Device support module | EPICS software that connects the records of an IOC to a device or protocol. The opcua device support module connects them to OPC UA servers. |
| Endpoint | An address of the server together with a security policy and a message security mode. A client connects to one endpoint. |
| Event | A message that the server reports from a source Object. An `event` line of a simulation file makes one each time its Boolean trigger becomes true, and an alarm makes one at each change of its state. |
| Information model | The nodes, the types, and the references that a server publishes. |
| IOC | An EPICS input output controller, a program that runs records. With the opcua device support module, its records read and write the tags of an OPC UA server. |
| Logic element | A rule that combines Variables in each simulation step: `pack`, `count`, or `on-delay`. |
| Memory tag | A tag of a PLC program that is not in a data block, in the area `Memory` of the model. |
| Message security mode | The protection of the messages of a session: None, Sign, or SignAndEncrypt. |
| Method | A function of an Object that a client calls with input arguments and that returns output arguments. |
| Namespace | A set of node ids that a URI identifies. The index of a namespace in the namespace table is the `ns=` part of a node id. |
| Node id | The identifier of a node, also written NodeId, in the form of text such as `ns=3;s="DataStatic"."myInt"`. |
| NodeSet loader | The part of open62541 that reads NodeSet2 files when the server starts. |
| NodeSet2 file | Also called NodeSet. An XML (Extensible Markup Language) file that defines the nodes and types of an information model. |
| OPC UA | Open Platform Communications Unified Architecture, a client and server protocol and information model standard for automation. |
| Operating state | The state of the simulated CPU: RUN or STOP. The Variable `OperatingMode` shows it, and the Boolean `Simulator.Run` changes it. |
| PKI store | A directory of certificates that an application trusts, as a public key infrastructure (PKI) store does, with the subdirectories `trusted/certs` and `issuers/certs`. |
| PLC | Programmable logic controller. |
| Probe | The client program `opcua-probe` that reads, writes, browses, and calls a running server. |
| Queue | The part of a simulation file that limits how many alarms of one source are active at once. The others are outstanding. |
| Security policy | The set of algorithms that protect a session, such as `Basic256Sha256`. |
| Self-signed certificate | A certificate that the key it certifies signed itself. |
| Session | The connection between a client and the server after the client has authenticated. |
| Signal | A rule that changes a Variable over time: `random`, `ramp`, `toggle`, or `sine`. |
| SIMATIC server interface | The standard information model that an S7-1500 CPU publishes, with fixed namespace indices, data blocks in areas, structured data types, alarms, and methods. |
| Simulation file | A text file that gives the server its behavior: signals, logic elements, alarms, events, methods, the operating state, and user accounts. |
| Simulation step | The action that the server repeats every `cycle` milliseconds to apply the signals, the logic elements, and the alarms. |
| Start value | The value that a Variable has when the simulation file is read and after each restart of the CPU, for a Variable that no signal drives. The `value` keyword sets it. |
| Structure | A data type with named members. The server sends a structured value as an ExtensionObject. |
| Subject alternative name | A field of a certificate that lists the identities, such as an application URI, that the certificate vouches for. |
| Subscription | A request of a client that the server reports changes of monitored items at a publishing interval. |
| Tag | A Variable of a PLC program: a member of a data block or a memory tag. |
| Variable | A node that holds a value. |
