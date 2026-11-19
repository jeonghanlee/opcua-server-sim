# opcua-server-sim

Test an OPC UA client, including an EPICS IOC, against a simulated Siemens S7-1500. The server uses open62541 1.5.10 and ships with an S7-1500 model that includes tags, methods, alarms, and RUN/STOP behavior.

## Start with the demo

The [Quick Start](docs/QUICKSTART.md) takes you from installation to a live server, a probe read, and an IOC read. It also lists the demo IOC's PVs. [Download the Quick Start PDF](docs/QUICKSTART.pdf).

## Documentation

- [Probe tutorial](docs/src/tutorial.md) for browsing and writing tags, calling a method, and checking RUN/STOP behavior.
- [IOC procedure](docs/src/procedures/ioc.md) for connecting an EPICS IOC and reading its PVs.
- [Full documentation](docs/src/SUMMARY.md) for build options, model files, and the command reference.
- [Model sources](docs/references.md) for the Siemens material behind the simulated model.

## License

See [Apache License 2.0](LICENSE) and [NOTICE](NOTICE).
