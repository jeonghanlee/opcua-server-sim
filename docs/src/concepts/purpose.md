# The reasons for imitating an S7-1500

The simulator imitates the OPC UA (Open Platform Communications Unified Architecture) server of a Siemens S7-1500 CPU (central processing unit). A client that talks to that device meets its information model, its limits, and its security settings, and not only the OPC UA protocol. This page explains which parts of the device the simulator copies and where the data comes from.

## What a client meets on a CPU

An S7-1500 CPU runs an OPC UA server. The server publishes the data blocks and memory tags of the PLC (programmable logic controller) program in a standard information model named the SIMATIC server interface. The model has fixed namespace indices, structured data types, data blocks that are organized in areas, alarms, and methods.

A client such as the EPICS (Experimental Physics and Industrial Control System) opcua device support module reads tags by node id, subscribes to them, writes them, and can connect over a secured session. A server that offers only the protocol does not exercise any of these paths in the way the device does.

## What the simulator copies

| Part of the device | How the simulator copies it |
| --- | --- |
| Information model | The composite model uses the namespace indices, the PLC object, the areas, the data types, and the naming of tags of the SIMATIC server interface. |
| System limits | `server.json5` carries the session count, the interval limits, and the item limits of a CPU 1515 or 1516. |
| Security | The server offers the security policies of the device with the message security modes Sign and SignAndEncrypt, and with user accounts. |
| Behavior | A simulation file changes values over time, raises alarms, answers methods, and switches between RUN and STOP. |
| Identity | The application URI (uniform resource identifier), the application name, and the namespace table follow the defaults of STEP 7 up to version V20. |

The CPU classes differ in their limits. The files `simulation-1511-1513.conf` and `simulation-1517-1518.conf` set the limits of two other classes on top of the shipped simulation.

## What the simulator leaves out

The server holds no program logic of a PLC. A value changes only when a simulation file says how, or when a client writes it. The file `docs/references.md` in the repository records the source of each element of the model and the documented behavior that the server does not reproduce.

## Pages that build on this concept

- [The architecture of the simulator](architecture.md) describes the parts of the simulator.
- [The composite model of the simulator](model.md) describes the information model.
- [Contents of the composite model](../reference/model-contents.md) lists the data blocks and the tags.
