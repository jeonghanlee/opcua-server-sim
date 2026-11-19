# Scope of the S7-1500 simulation

The simulator gives OPC UA clients a Siemens S7-1500 interface to work with. The model includes the PLC object, tag names, structured values, methods, and alarms that a client encounters on the controller.

| What a client uses | Where the simulator defines it |
| --- | --- |
| Browse paths, node IDs, and data types | The NodeSet2 files for [the composite S7-1500 model](model.md). |
| Session, interval, and item limits | [Server configuration](../reference/server-config.md). The default settings follow a CPU 1515 or 1516. |
| Message security | The security policies and application identity in `server.json5`. |
| Changing values, methods, alarms, and RUN/STOP | [The simulation file](simulation-file.md). |

The model serves the interface of the controller. Client writes and simulation rules drive its values. CPU profiles `simulation-1511-1513.conf` and `simulation-1517-1518.conf` change the limits used by the default simulation.

See [model contents](../reference/model-contents.md) for the tags you can use and [model sources](https://github.com/jeonghanlee/opcua-server-sim/blob/master/docs/references.md) for their provenance.
