# Probe client commands

The probe `opcua-probe` is a command-line OPC UA (Open Platform Communications Unified Architecture) client that checks a running server. This page lists its options, its commands, and the value types that the commands accept.

## Command line of the probe

The command line of the probe is:

```
opcua-probe [options] <endpoint-url> <command> [arguments]
```

| Option | Meaning |
| --- | --- |
| `-u <user>` | User name of the session. |
| `-p <password>` | Password of the session. |
| `-c <cert.der>` | Client certificate in DER (Distinguished Encoding Rules) form. Its application URI (uniform resource identifier) must be `urn:opcua-server-sim:probe`. |
| `-k <key.der>` | Private key of the client certificate in DER form. |
| `-P <policy>` | Security policy name, for example `Basic256Sha256`. It takes effect only when `-c` and `-k` are given; without them the session has no security and the probe prints no warning. |
| `-m <2 or 3>` | Message security mode: 2 for Sign, 3 for SignAndEncrypt. It takes effect only when `-c` and `-k` are given. |

The exit status is 0 when the command ran, 1 when the connection failed, and 2 for a usage error. The first word of the output of `read`, `write`, and `call` is the status name.

## Commands of the probe

| Command | Arguments | Output |
| --- | --- | --- |
| `read` | `<node>` | The status name and the value of a Variable. |
| `write` | `<node> <type> <value>` | The status name. Write an array with `<type>[]` and `<v1>,<v2>,...`. |
| `call` | `<object> <method> [<arg> ...]` | The status name and the output arguments. An argument is `<type>:<value>` or `<type>[]:<v1>,<v2>,...`. |
| `browse` | `<node>` | The forward hierarchical references of the node. |
| `refs` | `<node>` | All references of the node in both directions. |
| `endpoints` | none | The endpoints of the server. |
| `events` | `<node> <seconds> [<field> ...]` | The events that an Object reports within the time. Each field is a field of `SimaticEventType`, printed as `<field>=<value>`. |
| `intervals` | `[<node>]` | The revised publishing and sampling intervals for a request of 1 ms on a node. The default node is `CurrentTime`, whose sampling interval has a minimum of 100 ms; give a tag node to see the sampling minimum of the CPU (central processing unit) class. |
| `sessions` | none | Opens sessions until the server refuses one, and prints the counts. |
| `subscriptions` | `<count>` | Creates up to `<count>` subscriptions. |
| `items` | `<count>` | Creates `<count>` monitored items in one subscription. |

The probe reads a word that starts with `-` as an option, so a negative value of `write` needs `--` before the endpoint URL (uniform resource locator), for example `opcua-probe -- <endpoint-url> write <node> sbyte -3`. An argument of `call` such as `int16:-7` starts with its type and needs no `--`.

An associated value of an event is printed as `<switch>:<member>:<value>`. An alarm with a state that holds no value prints the switch 0. An event that holds no value has no such field and prints nothing.

## Value types of arguments

| Type | Meaning |
| --- | --- |
| `bool` | Boolean. |
| `sbyte`, `byte` | 8-bit integers, signed and unsigned. |
| `int16`, `uint16` | 16-bit integers, signed and unsigned. |
| `int32`, `uint32` | 32-bit integers, signed and unsigned. |
| `int64`, `uint64` | 64-bit integers, signed and unsigned. |
| `float`, `double` | Floating point numbers. |
| `datetime` | Time in 100 ns ticks since 1601. |
| `string` | Text. |
| `bytestring` | Bytes written as hexadecimal digits. |
| `text` | LocalizedText. |
