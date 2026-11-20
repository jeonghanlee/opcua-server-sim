# Simulation file keywords

Pass a simulation file with `-s` to set values and define the simulator's behavior. For the order in which these rules take effect, see [How the simulation runs](../concepts/simulation-file.md).

## Format of a line

- Each line is empty, a comment, or one keyword line.
- A line is a comment when its first word starts with `#`.
- Separate arguments with spaces or tabs. In rules that take NodeIds, put single quotes around a whole argument containing spaces, for example `value 'ns=2;s=Pump A.pressure' 2.5` or `'delay=ns=2;s=Pump A.delay'`. Double quotes in a NodeId remain literal. Inside a quoted argument, write a single quote twice: `value 'ns=2;s=Pump A''s pressure' 2.5` sets `Pump A's pressure`.
- A node id is written as OPC UA (Open Platform Communications Unified Architecture) text, for example `ns=3;s="DataStatic"."myInt"`.
- The server stops at the first line it cannot apply. It logs the file name and the line number.
- The default values are `min=0`, `max=100`, `step=1`, and `period=1000` for a signal, and 100 ms for `cycle`.

## Keywords and their effects

| Keyword | Arguments | Effect |
| --- | --- | --- |
| `cycle` | `<milliseconds>` | Sets the interval between simulation steps. The value must be greater than 0. |
| `include` | `<file>` | Reads another simulation file at this line. A name that is not absolute is relative to the directory of the file that holds the line. Includes nest at most 8 deep. |
| `limit` | `<name> <number>` | Sets a limit of the running server, or a count that the Server object reports. [Names of `limit`](#names-of-limit) lists the names. |
| `value` | `<node-id> <number>` | Sets a Variable to a number when the file is read. The number is the start value of the Variable. |
| `signal` | `<node-id> <kind> [min=<n>] [max=<n>] [step=<n>] [period=<ms>]` | Changes a Variable over time. [Signal kinds and behavior](#signal-kinds-and-behavior) lists the kinds. |
| `pack` | `<target-node-id> <bit-node-id> ...` | Collects Boolean Variables into the bits of an integer Variable. The first bit node is bit 0. |
| `count` | `<target-node-id> <bit-node-id> ...` | Writes the number of true Boolean Variables into the target. |
| `on-delay` | `<input-node-id> <output-node-id> delay=<ms or node-id> [elapsed=<node-id>]` | Sets the output after the input has been true for the delay, and clears the output when the input is false. The delay is a number of milliseconds or a Variable that holds it. The Variable named by `elapsed` receives the elapsed time. |
| `alarm` | `<type-node-id> <source-node-id> <trigger-node-id> <severity> <message>` | Defines an alarm with a state. The alarm becomes active when the Boolean trigger becomes true and inactive when it becomes false. Each change is an event of the condition type, reported from the source Object. Clients acknowledge the alarm with the Acknowledge method. |
| `event` | `<type-node-id> <source-node-id> <trigger-node-id> <severity> <message>` | Defines an event: one message each time the trigger becomes true, with no state. |
| `field` | `<trigger-node-id> <browse-name> <value>` | Sets an event field of the alarm or event that the trigger names. The line follows the `alarm` or `event` line. [Event fields of an alarm](#event-fields-of-an-alarm) lists the fields. |
| `queue` | `<max-node> <hysteresis-node> <current-node> <outstanding-node> <source-node> <overload-trigger-node>` | Defines an alarm queue. [Arguments of an alarm queue](#arguments-of-an-alarm-queue) describes the arguments. |
| `method` | `<node-id> <kind> [busy=<ms>] [in=<node-id>] [out=<node-id>]` | Defines how the server answers a method. [Method kinds and behavior](#method-kinds-and-behavior) lists the kinds. |
| `operating-mode` | `<node-id> run=<n> stop=<n>` | Names the Variable that shows the operating state and its values in RUN and in STOP. It adds the Boolean Variable `Simulator.Run` in the namespace `urn:opcua-server-sim:control`. Writing false to it puts the CPU in STOP, and writing true in STOP restarts the CPU. |
| `user` | `<name> <password>` | Adds a user account. |
| `anonymous` | `<yes or no>` | Sets whether a client can connect without a user account. The default is `yes`. |

The severity of an `alarm` or `event` line is a number from 1 to 1000. The message runs to the end of the line.

## Names of limit

| Name | Unit and range |
| --- | --- |
| `max-sessions` | Number of sessions, 1 to 65535. |
| `publishing-interval-min` | Milliseconds, 5 up to the configured maximum. |
| `sampling-interval-min` | Milliseconds, 5 up to the configured maximum. |
| `max-browse-continuation-points` | Reported count, 0 to 65535. |
| `max-query-continuation-points` | Reported count, 0 to 65535. |
| `max-history-continuation-points` | Reported count, 0 to 65535. |

The configured maximum of an interval is the maximum of the same interval limit in the server configuration file. A value above it is an error of the line.

## Signal kinds and behavior

| Kind | Behavior |
| --- | --- |
| `random` | Takes a random value in the range from `min` to `max` every period. |
| `ramp` | Adds `step` every period and restarts at `min` after `max`. |
| `toggle` | Alternates between `min` and `max` every period. |
| `sine` | Swings between `min` and `max` once per period. |

## Method kinds and behavior

| Kind | Behavior |
| --- | --- |
| `echo` | Returns the input arguments as output arguments. |
| `accept` | Returns no values. |
| `sum` | Returns the sum of the input arguments. |
| `sort` | Returns each input array in ascending order. |

The parameter `busy` is the time in milliseconds after an accepted call during which further calls fail. The parameters `in` and `out` name structure Variables of the method instance. They receive the input and the output arguments of the last call, and an argument goes to the member with the same name.

## Event fields of an alarm

The `field` keyword accepts the browse names of the following fields.

| Field | Value |
| --- | --- |
| `InfoText`, `AdditionalText_01` to `AdditionalText_09` | Text that runs to the end of the line. |
| `ID`, `DisplayClass` | A whole number up to 65535. |
| `GroupID` | A whole number up to 255. |
| `AssociatedValue_01` to `AssociatedValue_10` | `<member> <value>`, an associated value of the union `SimaticAssociatedAlarmValue`. |

The member of an associated value is one of `Invalid`, `Boolean`, `Int16`, `Int32`, `Int64`, `SByte`, `Byte`, `UInt16`, `UInt32`, `UInt64`, `Float`, `Double`, or `String`. The value is a whole number that fits the member, a floating point number, `true` or `false` (or `1` or `0`), or the rest of the line for a `String`. The switch field of the union is the position of the member counted from 1: `Boolean` is 2, `Int16` is 3, and `String` is 13.

## Arguments of an alarm queue

A queue holds the alarms with a state whose source Object is the source node. At most the value of the max node of them are active. The others are outstanding and become active, oldest first, when room frees.

| Argument | Meaning |
| --- | --- |
| `<max-node>` | Variable that holds the maximum number of active alarms. |
| `<hysteresis-node>` | Variable that holds the hysteresis of the overload. |
| `<current-node>` | Variable that receives the number of active alarms. |
| `<outstanding-node>` | Variable that receives the number of outstanding alarms. |
| `<source-node>` | Source Object of the alarms that belong to the queue. |
| `<overload-trigger-node>` | Boolean Variable that becomes true when the active alarms reach the maximum. It becomes false when no alarm is outstanding and the number of active alarms is below the maximum minus the hysteresis. An `alarm` line on it reports the overload alarm. |
