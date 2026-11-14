# opcua-server-sim

An OPC UA (Open Platform Communications Unified Architecture) server that imitates the OPC UA server of a Siemens S7-1500 controller, so that a client, for example an EPICS (Experimental Physics and Industrial Control System) IOC, can be tested without the device. It is built on open62541 1.5.10, loads its information model from NodeSet2 files, and takes its behavior from a simulation file.

## Build and run

With an open62541 installation `<open62541_install_path>` and the OPC Foundation NodeSet2 directory `<ua_nodeset_path>`:

```bash
make build OPEN62541_PATH=<open62541_install_path>
make probe OPEN62541_PATH=<open62541_install_path>
make run OPEN62541_PATH=<open62541_install_path> UA_NODESET_PATH=<ua_nodeset_path>
```

## Documentation

The book is in `docs/src/`; start with the [tutorial](docs/src/tutorial.md). The sources of the model data are in [docs/references.md](docs/references.md).

## License

Apache License 2.0; see `LICENSE` and `NOTICE`.
