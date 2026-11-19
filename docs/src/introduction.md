# S7-1500 OPC UA simulator

`opcua-server-sim` lets you test an OPC UA client against a simulated Siemens S7-1500. The default model includes readable and writable tags, structured values, methods, alarms, and CPU RUN/STOP behavior.

The simulator serves its model from NodeSet2 XML files. The server configuration sets connection and security options, and `simulation.conf` defines behavior. See [Simulator architecture](concepts/architecture.md) for how these pieces fit together.

## Find the right procedure

| Task | Start here |
| --- | --- |
| Install and verify the demo | [Quick Start](https://github.com/jeonghanlee/opcua-server-sim/blob/master/docs/QUICKSTART.md) |
| Learn what the simulator does | [Probe tutorial](tutorial.md) |
| Read simulated data with EPICS | [Run an IOC](procedures/ioc.md) |
| Find a node, command, or setting | [Model contents](reference/model-contents.md), [probe commands](reference/probe.md), or [Make targets and variables](reference/make.md) |
| Find the meaning of a term | [Glossary](glossary.md) |
