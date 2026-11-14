# The purpose of opcua-server-sim

`opcua-server-sim` is an OPC UA (Open Platform Communications Unified Architecture) server that imitates the OPC UA server of a Siemens S7-1500 CPU (central processing unit). It lets a controls engineer test a client against the information model, the limits, the security settings, and the behavior of that device without the device. This page explains what the simulator is, who this book is for, and where to find each topic.

## What the simulator is

The simulator is one C program built on the open62541 library, release 1.5.10. It holds no device knowledge: you give it a server configuration file, NodeSet2 XML (Extensible Markup Language) files that define the information model, and an optional simulation file that defines how values change over time. The repository ships the composite model `s7-1500-composite`, which holds the data blocks of several Siemens examples.

The repository also holds more parts. A probe client reads and writes a running server. A generator writes the NodeSet2 file of a model from a JSON (JavaScript Object Notation) description. The files of an EPICS (Experimental Physics and Industrial Control System) IOC (input output controller) read the model through the opcua device support module.

## Who this book is for

This book is for a controls engineer who knows EPICS and Linux and does not know open62541 or the OPC UA model of an S7-1500. It assumes that you can build a C program with `make` and run an IOC. The glossary defines the terms that the book uses.

## Where to find each topic

| You want to | Read |
| --- | --- |
| Build and use the simulator once, end to end | [Build the simulator and read a tag with the probe](tutorial.md) |
| Understand why and how the simulator is made | [The reasons for imitating an S7-1500](concepts/purpose.md), [The architecture of the simulator](concepts/architecture.md), [The composite model of the simulator](concepts/model.md), [The role of a simulation file in the server](concepts/simulation-file.md) |
| Do one task | [Build the server and the probe](procedures/build.md), [Create the server certificate](procedures/certificate.md), [Generate the NodeSet of a model](procedures/nodeset.md), [Run the simulator](procedures/run.md), [Run the tests](procedures/test.md), [Run an IOC against the simulator](procedures/ioc.md) |
| Look up an exact value | [Simulation file keywords](reference/simulation-keywords.md), [Server configuration keys](reference/server-config.md), [Model description format](reference/model-description.md), [Make targets and variables](reference/make.md), [Contents of the composite model](reference/model-contents.md), [Probe client commands](reference/probe.md) |
| Check a term | [Glossary of terms used in the book](glossary.md) |

Every command that a page shows runs as shown in a clean checkout of the repository, and the output that the page shows is the output of that command. The target `make book-check` runs the commands again and compares their output with the pages.
