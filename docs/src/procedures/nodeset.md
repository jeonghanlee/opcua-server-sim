# Generate the NodeSet of a model

The NodeSet2 XML (Extensible Markup Language) file of the composite model is generated from its description `plc.json`. This procedure writes the file again after you change the description, one of the XML section files in `models/s7-1500-composite/nodeset`, or the tool.

## Prerequisites

- A Linux host with `make` and `perl` in `PATH`.

The procedure has one step.

- In the repository root, write the NodeSet of the default model `s7-1500-composite`:

  ```bash
  make nodeset
  ```

The target writes `models/s7-1500-composite/s7-1500-composite.NodeSet2.xml` when the description, a section file, or the tool is newer than it. The tool replaces the file only when it has built the whole NodeSet. [Model description format](../reference/model-description.md) lists the keys of the description.

## Verification

Compare the file with the NodeSet that the tool writes to standard output. The command prints nothing and exits with status 0 when the two are identical:

```bash
perl tools/simatic-nodeset.pl models/s7-1500-composite/plc.json | cmp - models/s7-1500-composite/*.NodeSet2.xml
```
