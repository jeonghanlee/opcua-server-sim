# Generate the NodeSet of a model

Regenerate the composite model's NodeSet after editing its `plc.json`, its XML sections, or the generator.

## Prerequisites

- Have `make` and `perl` available. Run the commands from the checkout root.

Regenerate the NodeSet for `s7-1500-composite`.

```bash
make nodeset
```

The target writes `models/s7-1500-composite/s7-1500-composite.NodeSet2.xml` when an input changes. See [Model description format](../reference/model-description.md) for the keys in `plc.json`.

## Verification

Compare the generated file with a fresh result from the generator. A match exits successfully without output.

```bash
perl tools/simatic-nodeset.pl models/s7-1500-composite/plc.json | cmp - models/s7-1500-composite/*.NodeSet2.xml
```
