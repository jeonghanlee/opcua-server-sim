# How the simulation runs

The simulation file sets the model's initial values, server limits, user accounts, and rules for changes over time. The server reads it at startup when you supply `-s`. It reports the file and line if it cannot apply a line.

## What happens each cycle

The default interval is 100 ms. The composite model uses 50 ms to drive its 10 Hz clock bit.

1. Advance each periodic signal and write changed values to its variable.
2. Evaluate the logic rules `pack`, `count`, and `on-delay`.
3. Evaluate alarm triggers and the queues that limit how many alarms can be active.

The server handles method calls as clients make them. See [simulation file keywords](../reference/simulation-keywords.md) for the arguments to each rule.

## How RUN and STOP work

The `operating-mode` line defines the mode readback and adds `Simulator.Run` in the control namespace. With the composite model, the control is `ns=4;s=Simulator.Run`.

| Write to `Simulator.Run` | Result |
| --- | --- |
| `false` | Switch to STOP. Periodic updates pause, values remain readable and writable, and methods return `BadInvalidState`. |
| `true` while in STOP | Return to RUN. Ordinary variables reset to their start values, and signal-driven variables reset to the configured minimum. Random arrays receive random values after the first element. |

A client write persists until a simulation rule changes that variable or the simulated CPU restarts.

## Files included by profiles

A CPU profile can use `include` to load `simulation.conf` and then apply different limits and initial values. The shipped profiles cover CPU classes 1511 to 1513 and 1517 to 1518. See [the composite model's behavior](../reference/model-contents.md#behavior-of-the-shipped-simulation-file) for the default settings.
