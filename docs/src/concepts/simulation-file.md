# The role of a simulation file in the server

A simulation file turns the static information model into a model that behaves like a running CPU (central processing unit). The server reads the file once at start and repeats a simulation step at a fixed interval. This page explains what the file contains, what one step does, and how the operating state affects the step.

## Two phases of applying a simulation file

The server applies a simulation file in two phases.

- At start, the server reads each line in order. A line sets a start value, a limit, a user account, or registers a signal, a logic element, an alarm, a queue, or a method. The server stops at the first line it cannot apply.
- While it runs, the server calls the simulation step every `cycle` milliseconds. The default cycle is 100 ms, and the shipped simulation file sets 50 ms because the 10 Hz clock bit needs a step every 50 ms.

[Simulation file keywords](../reference/simulation-keywords.md) lists the lines.

## What one step does

One step runs three parts in this order:

- Each signal advances and writes its Variable when its value changes. A signal is a rule that changes one Variable over time: `random`, `ramp`, `toggle`, or `sine`.
- The logic elements evaluate. `pack` writes Boolean Variables into the bits of an integer, `count` writes the number of true Booleans, and `on-delay` sets an output after an input has been true for a delay.
- The alarms evaluate. An alarm follows a Boolean trigger Variable and reports its changes as events from a source Object. A queue limits how many alarms are active at once.

Methods are not part of the step. The server answers a method call when a client makes it, in the way the `method` line states.

## Start values and clients

A `value` line sets the start value of a Variable. A restart of the CPU returns every Variable to its start value, and every Variable that a signal drives to the minimum of that signal. A client can write a Variable whose access level allows it. The written value stays until a signal or a logic element changes it, or until the CPU restarts.

## The operating state of the CPU

The `operating-mode` line names the Variable that shows the operating state of the CPU, and adds the Boolean Variable `Simulator.Run` in the namespace `urn:opcua-server-sim:control`, which has the index 4 with the shipped model.

- Writing false to `Simulator.Run` puts the CPU in STOP. In STOP the simulation step does nothing: the signals and the logic elements hold their values, clients can read and write, and methods return `BadInvalidState`.
- Writing true in STOP restarts the CPU in RUN. The restart sets every Variable to its start value, and every Variable that a signal drives to the minimum of that signal. A `random` signal gives the elements of an array after the first one random values.

## Include files and CPU classes

A simulation file can include another file with the line `include`. A CPU class profile is such a file: it includes the shipped `simulation.conf` and then sets the limits of its class with `limit` lines and the queue sizes with `value` lines. The files `simulation-1511-1513.conf` and `simulation-1517-1518.conf` are profiles.

## User accounts of the simulated server

The `user` and `anonymous` lines define who can connect. The server applies them after it has read all files. The shipped file allows anonymous access and one account.

## Pages that build on this concept

- [Run the simulator](../procedures/run.md) starts the server with a simulation file.
- [Contents of the composite model](../reference/model-contents.md) lists the behavior of the shipped file.
