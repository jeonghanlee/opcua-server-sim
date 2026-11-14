# Model description format

The description of a model is a JSON (JavaScript Object Notation) file, `plc.json`, in the model directory. It lists the structures, data blocks, tags, method instances, and memory tags of a PLC (programmable logic controller) program. The tool `tools/simatic-nodeset.pl` writes the NodeSet2 XML (Extensible Markup Language) file of the model from it. This page lists the keys of the description and the options of the tool.

## Tool and its options

The command line of the tool is:

```
perl tools/simatic-nodeset.pl [--output <file>] <description.json>
```

| Option | Meaning |
| --- | --- |
| `--output`, `-o` `<file>` | Writes the NodeSet to this file. The file is replaced only when the whole NodeSet was built. Without the option the NodeSet goes to standard output. |
| `--help`, `-h` | Prints the help text. |

The exit status is 0 when the NodeSet was written, 1 for an error in the description or in file access, and 2 for a usage error.

## Syntax of the description file

The description is a JSON object. Comments that start with `#` and a comma after the last element are accepted.

## Top-level keys of the description

| Key | Value |
| --- | --- |
| `sections` | List of the parts of the NodeSet in output order. |
| `types` | Object that maps each SIMATIC data type name to its OPC UA (Open Platform Communications Unified Architecture) type. |
| `structures` | List of structures in definition order. |
| `blocks` | List of data blocks. |
| `memory` | List of memory tags. |

An entry of `sections` is one of the following:

| Entry | Effect |
| --- | --- |
| A file name | Inserts that XML file. The name is relative to the directory of the description. The text `@TYPE_DICTIONARY@` in the file is replaced by the binary type dictionary of all structures. |
| `@structures` | Inserts the generated nodes of the structures. |
| `@blocks` | Inserts the generated nodes of the data blocks. |
| `@memory` | Inserts the generated nodes of the memory tags. |

The tool adds the closing `UANodeSet` tag at the end.

## Keys of a type entry

| Key | Meaning |
| --- | --- |
| `alias` | DataType alias in the NodeSet. |
| `builtin` | OPC UA built-in type that carries the value. |
| `length` | Makes every tag of the type an array of that length. |

## Keys of a structure

| Key | Meaning |
| --- | --- |
| `name` | Text that follows `DT_` in the NodeId, quotation marks included. |
| `fields` | List of tags. |
| `browseName` | Browse name other than the name. |
| `existing` | Marks a structure whose type nodes a section file holds. |
| `system` | Places the type below `SimaticSystemStructures`. |
| `variableType` | When false, leaves out the VariableType. |
| `memberAccess` | Access level of the member Variables. |

## Keys of a data block

| Key | Meaning |
| --- | --- |
| `name` | Name of the block. Required. |
| `area` | Area folder of the block, `DataBlocksGlobal` or `DataBlocksInstance`. Required. |
| `comment` | Description of the block. Required. |
| `functionBlock` | Names the function block of an instance data block. |
| `flat` | Writes member NodeIds without quotation marks. |
| `tags` | List of tags. |
| `Inputs`, `Outputs`, `InOuts`, `Static` | Lists of the tags in that folder of an instance data block. |
| `method` | Object with the lists `in` and `out` of method arguments. |

## Keys of a tag

A tag is an object with the following keys. The memory tags and the arguments of a method use the same keys.

| Key | Meaning |
| --- | --- |
| `name` | Name of the tag. Required. |
| `type` | SIMATIC data type or structure name. Required. |
| `length` | Makes the tag an array of this length. |
| `start` | Start value. For an array it is a list, and for a structure it is an object that maps member names to values. |
| `access` | Access level: 1 for read, 3 for read and write. The default is 3. |
