# The composite model of the simulator

The composite model `s7-1500-composite` is the information model that the simulator serves by default. It is composite because it combines the data blocks of several Siemens examples and exports in one SIMATIC namespace, so that one server covers the cases that the examples cover separately. This page explains how the model is organized and how it is made.

## How the model is organized

The model has the layout of the SIMATIC server interface of an S7-1500 CPU (central processing unit).

- The PLC (programmable logic controller) object is the root. Its browse name is `3:PLC_1` and its node id is `ns=3;s=PLC`.
- The PLC object has the area folders. The global data blocks and the instance data blocks are in different areas, and the memory tags are in the area `Memory`.
- A data block holds tags. A tag is a Variable whose node id is the block name and the tag name in quotation marks, separated by a dot.
- An instance data block of a function block holds a method with its input and output parameters.
- A structured tag has a structure data type. The server sends it as an ExtensionObject, and the type dictionary describes its members.
- The device properties, such as the operating state `OperatingMode`, are children of the PLC object.

The SIMATIC namespace is index 3. The Device Integration (DI) NodeSet is index 2 and the server application URI (uniform resource identifier) is index 1.

## Why the model is composite

The data blocks come from several sources. The Siemens client example gives `DataStatic`, `DataSimulation`, and `InstUaMethodAdding`. The S7-1500 example database of the EPICS (Experimental Physics and Industrial Control System) opcua module gives `Data_block_1`. The export example of the function manual gives `Data_block_2`, and the production line example gives `Data_for_OPC_UA_Clients`, `Data_from_OPC_UA_Clients`, and `OpenDoor_DB`. A STEP 7 export gives `globalDB`. The other blocks cover cases of this model: every data type, an array data block, an IEC (International Electrotechnical Commission) timer, the alarm triggers, and four more methods. The file `docs/references.md` in the repository records the source of each block, or that the block is a choice of this model.

## How the model is made

The NodeSet2 XML (Extensible Markup Language) file of the model is generated. The tool `tools/simatic-nodeset.pl` reads `plc.json` and writes the file in the order of the `sections` list. The list holds fixed XML sections for the types, the device, the block types, the alarms, and the server. It also holds the generated nodes of the structures, the data blocks, and the memory tags. The target `make nodeset` runs the tool when the description, a section file, or the tool changed.

The model does not carry behavior. The values that change over time, the alarms, and the methods come from the simulation file.

## Pages that build on this concept

- [Contents of the composite model](../reference/model-contents.md) lists the data blocks and tags.
- [Model description format](../reference/model-description.md) lists the keys of `plc.json`.
- [Generate the NodeSet of a model](../procedures/nodeset.md) runs the tool.
