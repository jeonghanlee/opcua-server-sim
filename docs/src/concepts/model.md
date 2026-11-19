# The composite S7-1500 model

The default `s7-1500-composite` model combines several Siemens examples in one SIMATIC namespace. Use [model contents](../reference/model-contents.md) to find concrete tag names and method instances.

## Reading the model hierarchy

- The PLC (programmable logic controller) root is `ns=3;s=PLC`, with browse name `3:PLC_1`.
- Under the root, area folders group global data blocks, instance data blocks, and memory tags.
- A tag in a global data block usually has a node ID such as `ns=3;s="DataStatic"."myInt"`.
- An instance data block contains its method and the input and output parameters.
- Structured tags use structure data types. Their values travel as ExtensionObjects.
- Device properties such as `OperatingMode` are children of the PLC root.

The SIMATIC namespace is index 3. The server application URI is index 1 and Device Integration (DI) is index 2.

## Generating the NodeSet

`tools/simatic-nodeset.pl` reads `plc.json` and writes XML in the order of its `sections` list. The list combines fixed XML for device and data types, alarms, and the server with generated nodes for structures, data blocks, and memory tags.

See [the generation procedure](../procedures/nodeset.md) and [the description format](../reference/model-description.md). [Simulation rules](simulation-file.md) give the model its changing values, methods, and alarms.
