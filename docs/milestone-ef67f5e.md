# Work Register

Release line: master
Milestone index: ef67f5e
Canonical path: `docs/milestone-ef67f5e.md`
Canonical branch or ref: master
Git upstream: origin/master
Remote tracker: jeonghanlee/opcua-server-sim (no GitHub milestone)

Next session entry point: M1, M2, M3, and M8 are Complete. M9 and M4 stay Blocked on their open gates.

## Milestone

### Work

| Group | ID | Work unit | Type | Status | Ready | Deps | Done when / Evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Verify | M1 | IOC verification | Milestone | Complete | No | D7 | An EPICS IOC reads and writes the tags of the composite model and the checks T1 to T6 pass; [detail](#m1---ioc-verification) |
| Build | M2 | Simulator completeness | Milestone | Complete | No | D5 | The small and medium items of the owner's selection are built and tested by T1 to T9; [detail](#m2---simulator-completeness) |
| Build | M8 | Alarm associated values | Milestone | Complete | No | M2, D8 | Events carry `AssociatedValue_01` to `AssociatedValue_10` as the union type, shown by T1 and T2; [detail](#m8---alarm-associated-values) |
| Build | M9 | GoodOverload and registered nodes | Milestone | Blocked | No | M8, G4 | Each item is built and shown by T1 and T2, or retired by the decision of G4; [detail](#m9---goodoverload-and-registered-nodes) |
| Document | M3 | Technical documentation | Milestone | Complete | No | G2, D6, D9, D10, D11, D12 | The documentation book exists, every command in it ran as shown, and it passed second-person review; [detail](#m3---technical-documentation) |
| Deliver | M4 | Container image | Milestone | Blocked | No | G1, G3, D2, D13 | A container image runs the server with the composite model and answers a probe read; [detail](#m4---container-image) |
| Document | G2 | Owner decides the documentation format and the tutorial | External gate | Complete | No | | The owner records both choices in Decisions; [detail](#g2---owner-decides-the-documentation-format-and-the-tutorial) |
| Deliver | G1 | open62541-env changes committed | External gate | Open | No | D13 | The wrapper changes are committed on the branch `open62541-1.5` of the open62541-env repository; [detail](#g1---open62541-env-changes-committed) |
| Deliver | G3 | Owner decides the Dockerfile location and the image publication | External gate | Open | No | | The owner records both choices in Decisions; [detail](#g3---owner-decides-the-dockerfile-location-and-the-image-publication) |
| Build | G4 | Owner decides how to build GoodOverload and registered nodes | External gate | Open | No | | The owner records the decision in Decisions; [detail](#g4---owner-decides-how-to-build-goodoverload-and-registered-nodes) |

### Decisions

| ID | Decision | Decision Date |
| --- | --- | --- |
| D1 | Method instances, arguments, and their descriptions use names and behaviors defined by this project; the Siemens methods document is no longer a source | 2026-11-12 |
| D2 | The open62541 build requirements stay a prerequisite that the open62541-env wrapper provides; this repository checks the installed library and does not carry the wrapper changes | 2026-11-12 |
| D3 | The composite model `s7-1500-composite` is the default model of `make run` | 2026-11-12 |
| D4 | The application URI and application name keep the SIMATIC form of the imitated device | 2026-11-12 |
| D5 | Every candidate item of the simulator completeness work is selected, in the order small, medium, hard: M2 builds the small and medium items, M8 and M9 hold the hard ones | 2026-11-12 |
| D6 | The documentation is an mdBook book and has a tutorial | 2026-11-12 |
| D7 | The IOC startup and databases for the composite model live in `ioc/` of this repository and run through `iocsh.bash` of the site EPICS distribution; the distribution tree comes from one variable and the test is skipped when it is absent | 2026-11-13 |
| D8 | The `field` line sets an associated value as `field <trigger> AssociatedValue_<nn> <member> <value>`, with the member names of the union definition of the model | 2026-11-13 |
| D9 | The check of the commands of the book is a Perl tool in `tools/` that runs the marked commands of the procedure pages with a substitution table and has fault rows | 2026-11-13 |
| D10 | The book has a procedure page for running an IOC against the simulator, and the page of the tests names `EPICS_TREE` | 2026-11-13 |
| D11 | The reader of the book is a controls engineer who knows EPICS and Linux and does not know open62541 or the OPC UA model of a Siemens S7-1500 | 2026-11-13 |
| D12 | The title of the book is `opcua-server-sim` and its author is Jeong Han Lee, the copyright holder named in `NOTICE` | 2026-11-13 |
| D13 | The simulator builds open62541 1.5.10 from the branch `open62541-1.5` of the open62541-env repository; the master branch of that repository stays on open62541 1.3.15 for the EPICS opcua module | 2026-11-15 |

### Milestone Details

#### M1 - IOC verification

Origin: ef67f5e / M1
Identity History: none
GitHub Issue: #1 https://github.com/jeonghanlee/opcua-server-sim/issues/1
Status: Complete

##### Summary

The server was built to serve an EPICS IOC that uses the `opcua` device support module. The composite model has not been exercised with such an IOC. This work keeps an IOC startup and databases for the model in this repository and checks what the module reads and writes, with the module version of the site EPICS distribution (`opcua` 0.11.2 in release 1.5.0).

Premise checks, observed 2026-11-13 (recheck with the commands named):

- The loader `<tree>/base/bin/linux-x86_64/iocsh.bash -e <tree> -n <startup>` (`caget` and `caput` are in the same directory; none of the three is on `PATH`) resolves `module opcua` to `opcua 0.11.2` and `pvxs 1.5.3` in `~/epics/1.5.0/debian-13/7.0.10`. The startup file needs no application executable or DBD.
- With the module's own `opcuaIoc` against the simulator, `element=udtInt` and the nested `element=udtTime.YEAR` read 42 and 1970, the array `myArrayInt` and the element `myArrayInt[3]` read, and a write to `udtInt` reached the server and left `YEAR` unchanged. The module documents one pattern for a structure: a root record of type `opcuaItem` (`DEFACTN "read"`, `WOC "immediate"`) on the structure node and one element record per leaf with `@<root record> element=<path>`. Two records on one leaf fail at start (`can't add leaf to existing leaf udtInt`), so each member that is read and written has one bidirectional record. The checks below use this pattern; a write of the whole structure through the root record is not checked.
- The module help (`help opcua*`) has no method call command, so a method call cannot be checked with this version.
- A secured session opened 2026-11-13 with `opcuaSetupPKI <dir>` (the server certificate as `trusted/certs/server-cert.der`), `opcuaClientCertificate <cert> <key>`, and `opcuaSession ... sec-mode=SignAndEncrypt sec-policy=Basic256Sha256 sec-id=<file>` where the file holds `user=` and `pass=`: the IOC logged `connected as 'simulator' (username token)` and the server logged the user `simulator`. The client certificate must carry the URI `urn:ioc@<hostname>:EPICS:IOC` as its subject alternative name, otherwise the server refuses with `The client certificate's ApplicationUri could not be verified`. The option `ident-file=` is accepted without error and has no effect (the session connected as `Anonymous`).
- `iocsh.bash -S` ends only by a signal; without `-S` and with stdin at end of file the IOC exits at once. A test feeds the IOC through a fifo, waits for the prompt text `7.0.10 > ` in the log, runs its checks, and writes `exit` to the fifo; reproduced 2026-11-13 with the startup `module opcua` and `iocInit()` on dedicated ports: the prompt appeared, `iocRun: All initialization complete` was printed once, and the IOC ended after the write with no process left.

##### Scope

- `ioc/st.cmd` with `module opcua`, the session and subscription settings, and the databases for the composite model, kept in this repository. Runtime files and logs stay outside the repository and outside the distribution tree.
- Reads and writes of scalar tags, structure members including a nested member (`element=`), arrays, and one array element.
- Subscription updates of simulated values, the CPU RUN and STOP switch, and one secured session with a user account.
- `t/ioc.t`: starts the server and the IOC with dedicated Channel Access and PVAccess ports, skips when the variable for the distribution tree is empty or `iocsh.bash` is not found in it, and runs in `make test` and in `tools/mutation-check.pl`.

Out of scope: Alarms and Conditions (the module does not subscribe to events), a method call (the module version has no method support), changes to the server behavior (a defect becomes its own issue), and the IOC repository of any site.

Recorded 2026-11-13: the member nodes of `udtTime` (`YEAR`, `MONTH`, `DAY`, `WEEKDAY`, `HOUR`, `MINUTE`, `SECOND`, `NANOSECOND`) have `AccessLevel` 1 (read only) in the model NodeSet, so a client write to one returns `BadNotWritable`; the server-to-IOC direction of these members is not checked, and the IOC-to-server direction through the structure is checked by T2.

##### Completion Criteria

- Checks T1 to T6 have observed results recorded in Verification Results.
- A defect the IOC reveals is fixed in the server or recorded as its own issue before this work completes.

##### Dependencies And Decisions

- D7 (location of the IOC files and the way the test runs the IOC)

##### Implementation Plan

Plan Status: accepted
Plan Acceptance: 2026-11-13, with the variable names `EPICS_TREE` and `SIM_EPICS_TREE` accepted by the owner
Implementation Authorization: 2026-11-13 for the plan as accepted (the owner authorized the implementation; commit, push, and the edit of issue #1 are separate)
Superseded Plan Artifacts: none

1. `ioc/st.cmd` and the databases of the composite model; the make variable `EPICS_TREE` (the distribution tree) in `configure/CONFIG_SITE` with an empty default, given for example as `make test EPICS_TREE=~/epics/1.5.0/debian-13/7.0.10`, which `make test` passes to the test as `SIM_EPICS_TREE`; the test is skipped when the variable is empty or `<tree>/base/bin/*/iocsh.bash` does not exist. Closed by T1.
2. `t/ioc.t`: find `iocsh.bash`, `caget`, and `caput` in `<tree>/base/bin/*/`, start the server on a free port with a copy of the configuration, start the IOC through `iocsh.bash` fed by a fifo, wait for the prompt in the log (the line `7.0.10 > ` in this tree; the number is the EPICS base version of the tree), run the checks with `caget` and `caput`, stop the IOC with `exit` and the server with a signal. Closed by T1 to T5.
3. Records: a root `opcuaItem` record for `myUdt` with one bidirectional record per member, the arrays and one array element, the subscriptions, and the switch `ns=4;s=Simulator.Run`. Closed by T2 to T5.
4. Secured session: the test creates a client certificate with `openssl` whose subject alternative name is `urn:ioc@<hostname>:EPICS:IOC`, a PKI directory that trusts the server certificate, and an identity file with the account of `simulation.conf`; the startup file passes them with `opcuaSetupPKI`, `opcuaClientCertificate`, and `sec-id=`. Closed by T6.
5. Fault rows for each check in `t/mutations/server.json`, run with `tools/mutation-check.pl --make-var EPICS_TREE=<absolute path of the tree>`. Closed by the rule below the Test Plan.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| T1 | Integration | `t/ioc.t` starts the server and the IOC and reads the start values of the `DataStatic` scalar tags with `caget` | the shipped server and the site distribution on one host | the IOC reports the start values of the model; a copy of the tree with `myInt` start value 43 must fail this check |
| T2 | Integration | Read and write `myUdt` members `udtInt` and `udtTime.YEAR` through a root `opcuaItem` record and one record per member with `element=`; the member nodes on the server side are read and written with `opcua-probe` | the shipped server and the site distribution on one host | values read and written match in both directions and a write of one member leaves the others unchanged; a copy with member-to-structure propagation off must fail this check |
| T3 | Integration | Read and write `myArrayInt` and one element; the array and element nodes on the server side are read and written with `opcua-probe` | the shipped server and the site distribution on one host | the array and its element agree after a write; the same copy must fail this check |
| T4 | Integration | Watch `Clock_Byte` and `DataSimulation` values through records that scan on I/O interrupt | the shipped server and the site distribution on one host | the IOC records value changes without polling; a copy whose `pack` writes nothing must fail this check |
| T5 | Integration | Write the switch `Simulator.Run` false and true | the shipped server and the site distribution on one host | a record on `ns=3;s=OperatingMode` shows 4 and then 8 and values return to their start values; a copy that does not restore start values must fail this check |
| T6 | Integration | Open a secured session (`SignAndEncrypt`, `Basic256Sha256`) with the account of the simulation file and read a value | the shipped server and the site distribution on one host; `openssl` creates the client certificate | the IOC log names the user `simulator` and the read value matches the server; a copy with a wrong password for the account must fail this check |

Proving rule for M1 to M4, M8, and M9: before a check is relied on, the fault named in its row is applied to a scratch copy of the tree (`tools/mutation-check.pl` with a row in `t/mutations`), the unchanged tree is run through the same entry point first and must pass every check, and the check must fail for the named reason. A check without a run of its fault row is unproven.

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| T1 | 2026-11-13T11:51Z | server and IOC on one host (opcua 0.11.2, EPICS 7.0.10) | Pass | `make test EPICS_TREE=~/epics/1.5.0/debian-13/7.0.10` passed 300 checks (28 in `t/ioc.t`); row `m-start-myint` KILLED by `T1 myInt start value`, `m-start-mybyte` and `m-start-myword` by their T1 checks |
| T2 | 2026-11-13T11:51Z | server and IOC on one host (opcua 0.11.2, EPICS 7.0.10) | Pass | `make test EPICS_TREE=~/epics/1.5.0/debian-13/7.0.10` passed 300 checks (28 in `t/ioc.t`); rows `c-propagate-up-off` and `c-propagate-down-off` KILLED by the T2 checks named in `intended`, `m-udtint-readonly` by `T2 server write of udtInt reaches the IOC`. The member nodes of `udtTime` are not writable by a client (`opcua-probe write` returns `BadNotWritable`), so `YEAR` is checked in one direction: the IOC writes it through the structure and the probe reads it |
| T3 | 2026-11-13T11:51Z | server and IOC on one host (opcua 0.11.2, EPICS 7.0.10) | Pass | `make test EPICS_TREE=~/epics/1.5.0/debian-13/7.0.10` passed 300 checks (28 in `t/ioc.t`); row `c-propagate-up-off` KILLED by the two T3 checks named in `intended` |
| T4 | 2026-11-13T11:51Z | server and IOC on one host (opcua 0.11.2, EPICS 7.0.10) | Pass | `make test EPICS_TREE=~/epics/1.5.0/debian-13/7.0.10` passed 300 checks (28 in `t/ioc.t`); rows `c-pack-off` and `c-random-const` KILLED by the T4 checks named in `intended` |
| T5 | 2026-11-13T11:51Z | server and IOC on one host (opcua 0.11.2, EPICS 7.0.10) | Pass | `make test EPICS_TREE=~/epics/1.5.0/debian-13/7.0.10` passed 300 checks (28 in `t/ioc.t`); rows `c-restore-off`, `c-mode-swapped`, and `s-run-value` KILLED by the T5 checks named in `intended`; T5 waits for the mode to change before it judges, because the value of the step before can equal the expected value under `c-mode-swapped` |
| T6 | 2026-11-13T11:51Z | server and IOC on one host (opcua 0.11.2, EPICS 7.0.10) | Pass | `make test EPICS_TREE=~/epics/1.5.0/debian-13/7.0.10` passed 300 checks (28 in `t/ioc.t`); rows `c-password-wrong` and `m-start-mybyte` KILLED by the T6 checks named in `intended`, `s-user-password` KILLED by `t/server.t` |

Full table: `perl tools/mutation-check.pl --tree . --table t/mutations/server.json --work <directory outside the tree> --jobs 10 --make-var UA_NODESET_PATH=<UA-Nodeset directory> --make-var EPICS_TREE=<tree>` from 2026-11-13T11:18Z to 11:51Z: control run passed all 300 checks, 128 rows KILLED, 5 EQUIVALENT, none CHECK or SURVIVED. The rows of `t/mutations/server.json` whose intended checks include a `t/ioc.t` check are KILLED only when `EPICS_TREE` is given. `make test` without `EPICS_TREE` passed 272 checks and skipped `t/ioc.t`.

##### Closure Evidence

- Landed: commits `f377c90c5482094055665bb880403be1de8c4ca7` and `328b4b928ab94e13e42b69a9b049dd20bbf60980` pushed to `origin/master`. After `git fetch`, `git rev-parse HEAD origin/master` printed `328b4b928ab94e13e42b69a9b049dd20bbf60980` twice, observed 2026-11-13T16:39Z.
- Linked issue #1: the body was edited to the shipped state, a closing comment was posted, and the issue was closed with reason `completed`. `gh issue view 1 --repo jeonghanlee/opcua-server-sim` printed state `CLOSED`, state reason `COMPLETED`, closed at 2026-11-13T16:45:39Z.

#### M2 - Simulator completeness

Origin: ef67f5e / M2
Identity History: none
GitHub Issue: none
Status: Complete

##### Summary

The server does not reproduce part of the documented behavior of the imitated CPU. `docs/references.md` lists these items in its table of documented behavior without a counterpart in the server. The owner selected every candidate item on 2026-11-12 and set the order: small, medium, then hard (D5). This work builds the small and medium items; the hard ones are M8 and M9.

Premise checks, observed 2026-11-12 (recheck with the commands named):

- The diagnostic counters of the Server object already exist and change: with `make run` serving the composite model, `build/opcua-probe opc.tcp://localhost:4840 read i=2277` returned `Good 1` for `CurrentSessionCount` and `read i=2278` returned `Good 3` for `CumulatedSessionCount`. The installed open62541 defines `UA_ENABLE_DIAGNOSTICS`. The row "Diagnostic nodes of the CPU and their example values" in `docs/references.md` therefore describes the server wrongly; step 5 compares the node list of the manual with the server and corrects the row.
- The continuation point counts come from a compile-time constant of the library (`UA_MAXCONTINUATIONPOINTS` 32, defined in `src/server/ua_session.h` and used in `src/server/ua_server_ns0.c` of open62541). A reported value can be written; the real limit does not change.
- The server configuration file has keys for sessions, the two interval limits, and the subscription and monitored item counts globally (`maxSubscriptions`, `maxMonitoredItems`), per session (`maxSubscriptionsPerSession`), and per subscription (`maxMonitoredItemsPerSubscription`); `plugins/ua_config_json.c` of open62541 reads them and the installed library contains the key names. `server.json5` sets the per-session and per-subscription ones and not the two global ones. The configuration file has no key for the continuation point counts.
- The library returns `BadTooManySubscriptions` and `BadTooManyMonitoredItems` when a global or per-session or per-subscription count is reached. It returns `BadOutOfMemory` only when an allocation fails (`src/server/ua_services_subscription.c`), so that status code cannot be produced by a limit.
- The class values have two sources that differ in the publishing interval and the subscriptions per session. [14] for firmware V3.1.x gives sessions 32, 48, 64, sampling intervals 100, 100, 10 ms, and publishing intervals 200, 100, 10 ms for the 1511 to 1513, 1515 and 1516, and 1517 and 1518 classes. Slide 20 of [2] (May 2022) gives 500, 200, 10 ms and program alarm counts 100, 200, 400 and system diagnostics alarm counts 50, 100, 200 for the same classes. The plan takes the intervals and sessions from [14] and the alarm counts from [2].
- The monitored item limits of [14] are per subscription: at most 10,000 items, and a subscription created with at most 1000 items cannot grow past 1000; more items answer `BadTooManyMonitoredItems`. The figure over all subscriptions (4000, 4000, 24,000) is a recommended maximum and no limit, and `BadOutOfMemory` is named for a quantity framework without a number. The subscription counts (20 of up to 1000 items, 10 of more, 50 per session) are the same in the three classes.

##### Scope

In the order of the owner's selection:

1. CPU class limit profiles: the limits of the 1511 to 1513 and the 1517 to 1518 classes next to the current 1515 and 1516 set, including the alarm queue sizes of each class.
2. Event fields `InfoText`, `AdditionalText_01` to `AdditionalText_09`, `ID`, `DisplayClass`, and `GroupID`.
3. The continuation point counts of the Server object (5).
4. The diagnostic nodes: verify against the manual and correct the document.
5. The overload alarm with its alarm count limit, outstanding count, and release threshold, and an example alarm of the system diagnostics category.
6. The subscription count limit and the monitored item limit per subscription, set in `server.json5`, with the status codes `BadTooManySubscriptions` and `BadTooManyMonitoredItems`; the rule that a subscription of up to 1000 items cannot grow past 1000 is built only when the library allows it, otherwise the reduced scope is recorded.

Out of scope: Associated values (M8), `GoodOverload` and registered nodes (M9), `BadOutOfMemory` at a limit (the library returns it only when an allocation fails), and changes to open62541.

##### Completion Criteria

- Checks T1 to T9 have observed results recorded in Verification Results.
- The table of documented behavior without a counterpart in `docs/references.md` lists only items that are still not built.
- Every test that passed before the change still passes.

##### Dependencies And Decisions

- D5 (selection and order)

##### Implementation Plan

Plan Status: accepted
Plan Acceptance: 2026-11-12, revised the same day: `intervals` takes an optional node; step 6 uses the keyword `queue` and T5 sets the hysteresis (both accepted by the owner)
Implementation Authorization: 2026-11-12 for the plan as revised (the owner authorized the implementation; commit and push are separate)
Superseded Plan Artifacts: none

1. `src/opcua_server_sim.c`: add the simulation keywords `include <file>` (relative to the including file), `limit <name> <number>` for the limits of the running server that a profile file overrides and for the reported counts that the configuration file cannot set, with the names `max-sessions`, `publishing-interval-min` and `sampling-interval-min` (milliseconds), `max-browse-continuation-points`, `max-query-continuation-points`, and `max-history-continuation-points` (any other name is an error of the line), and `value <node-id> <number>` to set a Variable at start. `tools/opcua-probe.c`: add the commands `intervals [<node-id>]` (one subscription with a publishing interval of 1 ms and one monitored item on the node, `i=2258` when none is given, with a sampling interval of 1 ms; prints `Good publishing=<ms> sampling=<ms>` from the revised values; the revised sampling interval is raised to the `MinimumSamplingInterval` of the node, so the checks name a node with -1), `sessions` (opens sessions, the probe's own included, until the server refuses one or 200 are open; reads `CurrentSessionCount` (`i=2277`) while all of them are open, prints `Good accepted=<n> refused=<status> current=<n>`, and closes them), `subscriptions <count>` (creates up to <count> subscriptions in one session; prints `Good created=<n> refused=<status>`, with `Good` as status when none was refused), and `items <count>` (one subscription, then <count> monitored items on `i=2258` in calls of 1000 items; prints `Good created=<n> refused=<status>`); extend `events <node> <seconds>` to `events <node> <seconds> [<field> ...]`, which adds each named field of `SimaticEventType` to the select clauses and prints ` <field>=<value>` after the fixed fields. Closed by T9.
2. `models/s7-1500-composite`: add the profile files `simulation-1511-1513.conf` and `simulation-1517-1518.conf` for the 1511 to 1513 and the 1517 to 1518 classes, each including `simulation.conf` and overriding the limits and the alarm queue sizes. The intervals and session counts come from [14] for firmware V3.1.x, the alarm queue sizes from slide 20 of [2] (program alarms 100, 200, 400; system diagnostics alarms 50, 100, 200). Closed by T1.
3. `src/opcua_server_sim.c`: add the keyword `field <trigger-node-id> <browse-name> <value>` that sets an event field of an alarm or event (the value is the rest of the line, stored by the data type of the field in `nodeset/alarms.xml`: LocalizedText for `InfoText` and `AdditionalText_01` to `AdditionalText_09`, UInt16 for `ID` and `DisplayClass`, Byte for `GroupID`; an unknown browse name or a value that does not fit the type is an error of the line); add example lines to `simulation.conf`. Closed by T2.
4. `simulation.conf`: add the `limit` lines for the three continuation point counts. Closed by T3.
5. Compare the diagnostic node list of the manual with the server; add a test for the nodes and counters; correct the row in `docs/references.md`. Closed by T4.
6. `src/opcua_server_sim.c`: add the keyword `queue <max-node> <hysteresis-node> <current-node> <outstanding-node> <source-node> <overload-trigger-node>`. The alarms with a state whose source Object is <source-node> belong to the queue. At most the value of <max-node> of them are active; the others are outstanding and become active, oldest first, when room frees. <current-node> holds the number of active alarms and <outstanding-node> the number of outstanding ones. The Bool Variable <overload-trigger-node> becomes true when the number of active alarms reaches the maximum and false when no alarm is outstanding and the number is below the maximum minus the value of <hysteresis-node>; an `alarm` line on that Variable reports the overload alarm with the type `SimaticAlarmConditionType`, because the manual names no separate type. `plc.json`: add the Bool tags `Program_Alarm_3`, `System_Alarm`, `Overload_Program`, and `Overload_System` to the data block `AlarmTriggers`; run `make nodeset`. `simulation.conf`: add a `queue` line for the program alarms and one for the system diagnostics alarms, the alarm lines of the two new alarms and of the two overload alarms, and remove the `count` line of `CurrentAlarmsInQueue`, which the queue replaces. Closed by T5 and T6.
7. `models/s7-1500-composite/server.json5`: set `maxSubscriptions` to 30 (20 and 10 of [14]); `maxSubscriptionsPerSession` 50 and `maxMonitoredItemsPerSubscription` 10000 are set already, and `maxMonitoredItems` stays unset because [14] gives only a recommendation for it. The library takes one value per limit, so the two-tier rule of 1000 and 10,000 items is recorded as not built. Closed by T7.
8. Update the keyword text at the top of `simulation.conf`, update `docs/references.md`, and run the whole test suite. Closed by T8.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| T1 | Integration | Start the server with `make run` and with `make run MODEL_SIMULATION=<absolute path of the profile file>` for each of the two profile files; run `opcua-probe intervals 'ns=3;s="DataStatic"."myInt"'` and `opcua-probe sessions` | the shipped server and probe | the revised minimum publishing and sampling intervals and the accepted session count match the class: 100 ms, 100 ms, 48 for the 1515 and 1516 class; 200 ms, 100 ms, 32 for the 1511 to 1513 class; 10 ms, 10 ms, 64 for the 1517 and 1518 class; a profile file that keeps the 1515 values must fail this check |
| T2 | Integration | Run `opcua-probe events <node> <seconds> InfoText AdditionalText_01` while an alarm and an event whose lines carry `field` settings are raised | the shipped server and probe | the events carry the configured `InfoText` and `AdditionalText_01` values; a copy that ignores `field` lines must fail this check |
| T3 | Integration | Read `i=2735`, `i=2736`, and `i=2737` (before the change `Good 32`, `Good 0`, and `Good 0`) | the shipped server and probe | each reads `Good 5`; a copy without the `limit` lines must fail this check |
| T4 | Integration | Run `opcua-probe browse i=2275` and `opcua-probe sessions` | the shipped server and probe | `browse` lists the twelve members and `sessions` prints `current` equal to `accepted`; a copy that lacks one member must fail this check |
| T5 | Integration | With the lines `value ns=3;s=SimaticAlarmsAndConditions.ProgramAlarms.MaxAlarmsInQueue 2` and `value ns=3;s=SimaticAlarmsAndConditions.Overloads.OverloadHysteresis 1` in the simulation file, raise the triggers `Program_Alarm_1`, `Program_Alarm_2`, and `Program_Alarm_3` of `AlarmTriggers` one after the other, then clear them in the same order | the shipped server and probe | after the second trigger `Overload_Program` is true and the overload alarm is reported; after the third `OutstandingProgramAlarms` reads 1 and `CurrentAlarmsInQueue` 2; clearing the first alarm makes the third active (`OutstandingProgramAlarms` 0, `CurrentAlarmsInQueue` 2, `Overload_Program` still true); `Overload_Program` is false only after the last alarm is cleared, when no alarm is outstanding and the count 0 is below the limit 2 minus the hysteresis 1; a copy that ignores the hysteresis must fail this check |
| T6 | Integration | Subscribe to the system diagnostics notifier and write `true` to `ns=3;s="AlarmTriggers"."System_Alarm"` | the shipped server and probe | the notifier reports the event; a copy that does not report the example alarm must fail this check |
| T7 | Integration | Run `opcua-probe subscriptions 31` and `opcua-probe items 10001` | the shipped server and probe | `subscriptions 31` prints `Good created=30 refused=BadTooManySubscriptions` and `items 10001` prints `Good created=10000 refused=BadTooManyMonitoredItems`; a copy without `maxSubscriptions` in `server.json5` must fail this check |
| T8 | Integration | `make test` | the shipped server and probe | all tests pass, including the tests that existed before this work; the mutation rows of the baseline below still fail the same checks |
| T9 | Integration | In `t/server.t`, start the server with simulation files that use `include`, `limit`, and `value` correctly and incorrectly (unknown limit name, non-numeric value, missing include file, unknown node) | the shipped server and probe | a correct line takes effect on the observed value or limit; an incorrect line makes the server exit with status 1 and name its line; a copy that ignores a keyword or accepts an incorrect line must fail this check |

Check design of the checks that share one server run (T1, T4, and the keyword run of T9). The expected value of every check comes from the simulation file text or from the cited source, never from the observed output.

| Check | Claim and source | Inputs and distance from the boundary | State read and the step that sets it | Expected value and its condition |
| --- | --- | --- | --- | --- |
| value sets a Variable | `value` writes a number and the number is the start value (plan step 1) | 7 against the model start value 42 and the later write 99; no boundary | `myInt` read after start (set by the `value` line), after the check writes 99, after STOP and RUN (set by the check) | 7 from the file text; holds because 7 differs from both other values |
| limit of sessions | `max-sessions` replaces the configured 48 (plan step 1) | 5 against 48; the probe's own session counts | the `sessions` command opens until a refusal and reads `CurrentSessionCount` while all are open | `accepted=5 refused=BadTooManySessions current=5`; the readiness probe of the test closes its sessions before the check |
| limit of intervals | `publishing-interval-min` and `sampling-interval-min` replace 100 and 100 (plan step 1) | 200 and 50 against 100 and 100 | `intervals` requests 1 ms on a Variable whose `MinimumSamplingInterval` is -1, which is observed for `ns=3;s="DataStatic"."myInt"`; it is 100 for `CurrentTime` and raises the revised value to 100 | `publishing=200 sampling=50`; holds only for a node with `MinimumSamplingInterval` below the configured minimum |
| limit of continuation points | the three names write the three Server nodes (plan step 1) | 5, 6, 7 against the observed 32, 0, 0; distinct values expose a swapped name | `i=2735`, `i=2736`, `i=2737` read after start | 5, 6, 7 from the file text |
| rejected lines | an unknown name, a text, a fraction, a value below the smallest interval, a missing or recursive include, an unknown node, and a node that is no Variable each stop the server | interval 1 against the smallest accepted value 5, which is the plan's boundary; the other inputs are not near a boundary | one simulation file per case, written by the check | exit status 1 and `line N cannot be applied` with N the line of the file text |
| class profiles (T1) | sessions, sampling and publishing minimum of each class ([14] V3.1.x) | three profile files; the values 32, 48, 64 and 100, 100, 10 and 200, 100, 10 differ across classes | `make run MODEL_SIMULATION=<profile>` starts a fresh server per class | values of [14] for firmware V3.1.x; the sampling value needs the `-1` node above |
| sessions and diagnostics (T4) | `CurrentSessionCount` equals the open sessions (plan step 5) | 48 open sessions | `sessions` reads the counter while its sessions are open | `current` equals `accepted`; `browse i=2275` lists twelve members |

Plan of the execution safeguards of the test reference:

| Safeguard | Criteria | Evidence location |
| --- | --- | --- |
| 1 volume | `items 10001` runs against the real server once before T7 is relied on; its run time and `created` count are recorded | the run output in the Verification Results row of T7 |
| 2 expected values | every expected number has a source in this table; a value the sources leave open goes to the owner | this table and the sources of the plan |
| 3 time values | no check compares timestamps; the intervals are durations the server returns | not applicable |
| 4 fault application | each fault row of the mutation tables reaches the real path: the old text occurs once and the SHA-256 of the mutated file equals the file the run used | the output of `tools/mutation-check.pl` |
| 5 measurement meaning | `sessions` counts its own session; `CurrentSessionCount` is a gauge read while the sessions are open; a sampling interval is bounded by the node's `MinimumSamplingInterval` | this table |
| 6 source and proof | the checks run through `make test` and the mutation tool runs `make test` in each copy | the control line and each row of the tool output |
| 7 case coverage | T1 has three profile cells times three values; T9 has one run and one case per rejected line, listed above | the Verification Results rows |

Baseline of the tests that exist before M2, observed 2026-11-12 with `tools/mutation-check.pl` on the 68 fault rows that existed then: 52 rows of `t/mutations/server.json` (34 in `src/opcua_server_sim.c`, 18 in model and configuration files) and 16 rows of `t/mutations/tools.json` (in `tools/simatic-nodeset.pl`). The work of M2 added rows, so the tables now hold 133 and 16 rows. The unchanged copy passed all 151 checks through `make test` before each series. 67 rows failed the intended checks and nothing outside the expected set; 1 row (`c-second-mode-allowed`) is equivalent: the second `add_mode_switch` fails on the existing node, so the repeat guard of `operating-mode` changes no observable. Recheck: `perl tools/mutation-check.pl --tree . --table t/mutations/server.json --work <empty-dir-outside-the-tree> --make-var UA_NODESET_PATH=<absolute-path-of-ua-nodeset>`, and the same with `tools.json`; each command runs every row of its table, so the count differs from the 68 rows above.

The first run found four gaps, which are closed by new checks that each fail on their fault row: writing a whole array is followed by an element read (`array: an element follows a write of the whole array`), the dictionary checks of `t/simatic-nodeset.t` decode the tool output, `STOP: a write is accepted` fails when `udtInt` is read-only, and `usage: exit status` and `usage: the message names the arguments` run the server without arguments. The probe command `write` takes `<type>[]` with a comma-separated list for the array check.

Rule for later work: a new check gets its fault row in the table when the check is written, and the series is rerun after a change of `src/opcua_server_sim.c` or the model files; a row whose old text no longer occurs once stops the run and is corrected first.

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| T1 | 2026-11-12T22:12Z | the shipped server and probe through `make run` on this host | Passed | `make run MODEL_SIMULATION=<profile>` and `opcua-probe intervals 'ns=3;s="DataStatic"."myInt"'`, `sessions`, and reads of the two `MaxAlarmsInQueue` nodes gave for the default file `publishing=100 sampling=100`, `accepted=48`, 200 and 100; for `simulation-1511-1513.conf` `publishing=200 sampling=100`, `accepted=32`, 100 and 50; for `simulation-1517-1518.conf` `publishing=10 sampling=10`, `accepted=64`, 400 and 200. `make test` passed 203 checks including the class checks of `t/server.t`; 12 fault rows `s-profile-*` of `t/mutations/server.json` failed the intended checks |
| T2 | 2026-11-12T22:33Z | the shipped server and probe on this host | Passed | `opcua-probe events ns=3;s=SimaticAlarmsAndConditions 12 InfoText AdditionalText_01 ID DisplayClass GroupID` against the shipped simulation file printed the configured `InfoText` and `AdditionalText_01` for the event of `Program_Alarm` and the five fields for the alarm of `Program_Alarm_2`. `make test` passed 224 checks including the field run and seven rejected `field` lines; 18 fault rows `c-field-*`, `p-events-*`, `s-field-*` of `t/mutations/server.json`: 16 failed the intended checks, 2 are equivalent because the server resolves the field path on the event instance without checking the declaring type |
| T3 | 2026-11-12T22:45Z | the shipped server and probe on this host | Passed | `i=2735`, `i=2736`, and `i=2737` read `Good 5` each with the shipped simulation file; before the change they read `Good 32`, `Good 0`, and `Good 0`. `make test` passed 227 checks including the three continuation point checks; 4 fault rows `s-limit-*` of `t/mutations/server.json` failed the intended checks |
| T4 | 2026-11-12T22:52Z | the shipped server and probe on this host | Passed | `opcua-probe browse i=2275` lists twelve members including `CurrentSessionCount` `i=2277` and `SecurityRejectedSessionCount` `i=2279`; `browse i=3706` lists `SessionDiagnosticsArray` `i=3707` and `read i=3707` shows `ActualSessionTimeout`; `browse i=2274` lists `SubscriptionDiagnosticsArray` `i=2290`; `opcua-probe sessions` printed `accepted=48 refused=BadTooManySessions current=48`. The nodes named on pp. 357-358 of the manual all exist. `make test` passed 234 checks including 7 diagnostics checks; 4 fault rows `c-diagnostics-*` of `t/mutations/server.json` (a node deleted at start) failed the intended checks; the row of `docs/references.md` moved to the table of server behavior |
| T5 | 2026-11-12T23:42Z | the shipped server and probe on this host | Passed | `make test` ran the shipped server with `value` lines for a limit of 2 and a hysteresis of 1 and passed 266 checks: `Overload_Program` became true with two active alarms and the overload alarm was reported (`message="Overload of the program alarms" severity=900`); the third alarm left `OutstandingProgramAlarms` at 1 and `CurrentAlarmsInQueue` at 2; after the first alarm was cleared the third became active (`OutstandingProgramAlarms` 0); `Overload_Program` stayed true at 1 alarm and became false at 0 alarms. A run with a limit of 1 showed that two outstanding alarms leave in the order they came and that an outstanding alarm that goes out is dropped, and that the system diagnostics queue overloads at its limit. 19 fault rows `c-queue-*`, `s-queue-*`, `s-overload-*`, `s-system-alarm-*`, `s-program-alarm-3-removed`, `m-plc-tag-removed` of `t/mutations/server.json`: 18 failed the intended checks and `c-queue-outstanding-release-off` is equivalent because an outstanding alarm exists only while the active alarms are at the maximum |
| T6 | 2026-11-12T23:42Z | the shipped server and probe on this host | Passed | `make test` passed 266 checks including the subscription to `ns=3;s=SimaticAlarmsAndConditions.SystemDiagnostics` and the write of `true` to `ns=3;s="AlarmTriggers"."System_Alarm"`: the notifier reported `message="System diagnostics alarm" severity=500 source=SystemDiagnostics active=1 acked=0 retain=1`; the fault rows `s-system-alarm-removed` and `s-system-alarm-severity` failed the intended checks |
| T7 | 2026-11-12T23:00Z | the shipped server and probe on this host | Passed | with the shipped configuration `opcua-probe subscriptions 31` printed `Good created=30 refused=BadTooManySubscriptions` in 0.12 s and `opcua-probe items 10001` printed `Good created=10000 refused=BadTooManyMonitoredItems` in 0.16 s (11 calls of at most 1000 items; the server log held 20103 lines). `make test` passed 236 checks including both; 5 fault rows `m-max-*` and `p-subscriptions-count`, `p-items-count` of `t/mutations/server.json` failed the intended checks. The rule of 1000 and 10,000 items per subscription is not built: the library takes one value per limit |
| T8 | 2026-11-13T02:07Z | the shipped server and probe on this host | Passed | `make test` passed 272 checks (the 151 checks of the baseline and the checks of T1 to T7 and T9). `tools/mutation-check.pl` ran on the final tree with a control run of 272 passing checks first: `t/mutations/tools.json` 16 rows, all failed the intended checks; `t/mutations/server.json` 133 rows, 128 failed the intended checks and 5 are equivalent (`c-second-mode-allowed`, `c-value-class-check-off`, `p-events-one-type`, `p-events-alarm-clause-off`, `c-queue-outstanding-release-off`). No row reported an unexpected failure or an incomplete run. The 68 rows that existed before M2 are among them and failed the same checks as in the baseline. After the series started, only the messages of `tools/mutation-check.pl` changed, which the tests do not use. `make test` also passed with a server holding port 4840 |
| T9 | 2026-11-12T21:59Z | the shipped server and probe through `make test` and `tools/mutation-check.pl` on this host | Passed | `make test` passed 185 checks including the keyword run and the rejected lines of `t/server.t`; 18 fault rows of `t/mutations/server.json` (`c-include-*`, `c-limit-*`, `c-value-*`, `p-sessions-*`, `p-intervals-*`): 17 failed the intended checks, `c-value-class-check-off` is equivalent because `write_number` fails on a node that is no Variable |

##### Closure Evidence

- Landed: commit `358bbd3915f6dba26c8abbf3ebe3cae75ef24670` on `master`, pushed to `origin/master`. Observed 2026-11-13T02:56Z after `git fetch`: `HEAD` and `origin/master` are the same commit, ahead and behind are 0 and 0, `git diff --stat HEAD origin/master` is empty, and `origin/master` holds the 34 committed paths and `LICENSE`. Recheck: `git -C <repository> fetch`, then `git -C <repository> rev-parse HEAD origin/master`.
- Checks: T1 to T9 are recorded as Passed above; the commit holds the tree on which T8 ran, except that `docs/milestone-ef67f5e.md` records these results.
- External gates: none.

#### M8 - Alarm associated values

Origin: ef67f5e / M8
Identity History: none
GitHub Issue: #2 https://github.com/jeonghanlee/opcua-server-sim/issues/2
Status: Complete

##### Summary

An alarm event carries up to ten associated values, `AssociatedValue_01` to `AssociatedValue_10`, of the union type `SimaticAssociatedAlarmValue` (`ns=3;i=1809`, encoding `ns=3;i=1810` in the model). The server publishes none. The owner selected this item as a hard one (D5).

Premise, read 2026-11-12 in the open62541 sources: the NodeSet loader turns a data type definition with `IsUnion` into a union data type (`DataTypeImporter.c` of the nodesetLoader backend).

Premise checks, observed 2026-11-13 (recheck with the commands named):

- The union is registered: `opcua-probe read 'ns=3;s=SimaticEventType.AssociatedValue_01'` on the running server returns an ExtensionObject with the encoding id `ns=3;i=1810` and a body of four zero bytes, which is the switch field 0.
- The members of the union in the model are, in order, `Invalid`, `Boolean`, `Int16`, `Int32`, `Int64`, `SByte`, `Byte`, `UInt16`, `UInt32`, `UInt64`, `Float`, `Double`, and `String` (`nodeset/alarms.xml`). The switch field is the position of the member counted from 1: Boolean 2, Int16 3, Int32 4, Int64 5, SByte 6, Byte 7, UInt16 8, UInt32 9, UInt64 10, Float 11, Double 12, String 13.
- An alarm event on the notifier `ns=3;s=SimaticAlarmsAndConditions` carries `InfoText` and no associated value (`opcua-probe events ... InfoText AssociatedValue_01 AssociatedValue_02`).
- The server finds a data type by its node id with `UA_Server_findDataType` (`src/opcua_server_sim.c`).

Hypothesis: an encoded value of the registered union has the switch field of the member position. The first step checks it with an event.

##### Scope

Setting associated values of an alarm and an event from the simulation file, and publishing them as the union in the event fields.

Out of scope: The text placeholders that clients resolve in the alarm message.

##### Completion Criteria

- An event carries associated values whose switch field is the position of the member in the union definition of the model, counted from 1, and whose member holds the configured value.

##### Dependencies And Decisions

- M2 (work ordering set by D5)
- D8 (the form of the `field` line for associated values)

##### Implementation Plan

Plan Status: accepted
Plan Acceptance: 2026-11-13, with the form of the `field` line decided as D8
Implementation Authorization: 2026-11-13 for the plan as accepted (the owner authorized the implementation; commit and push are separate)
Superseded Plan Artifacts: none

1. Check that an encoded value of the registered union has the switch value of the member position; if it does not, register the type from its definition at start. Closed by T1.
2. Extend the `field` keyword of M2 step 3 to associated values: `field <trigger> AssociatedValue_<nn> <member> <value>`, where `<nn>` is 01 to 10 and `<member>` is the name of a member of the union definition of the model (D8). Update the description of `field` in the header of `simulation.conf` and in the comment of `parse_field` in `src/opcua_server_sim.c`. Closed by T1 and T2.
3. Extend the probe client to print an associated value. Closed by T1.
4. Add the tests T1 and T2 in `t/server.t` and a fault row for each in `t/mutations/server.json` (a copy that writes a wrong switch value for T1, a copy that accepts any member name for T2), and run the rows with `tools/mutation-check.pl`. Closed by T1, T2, and the proving rule under the Test Plan of M1.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| T1 | Integration | Set associated values of several member types on an event (`Program_Alarm`) and on an alarm with a state (`Program_Alarm_2`), raise each, and subscribe through the probe | the shipped server and probe | each event field shows the switch value and the member value that was configured; a copy that writes a wrong switch value must fail this check |
| T2 | Integration | In `t/server.t`, start the server with simulation files that set an associated value correctly and incorrectly (unknown member name, a value that does not fit the member type, a field number outside 01 to 10) | the shipped server and probe | a correct line takes effect on the event field; an incorrect line makes the server exit with status 1 and name its line; a copy that accepts any member name must fail this check |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| T1 | 2026-11-13T20:08Z | the shipped server and probe on this host | Pass | `make test EPICS_TREE=~/epics/1.5.0/debian-13/7.0.10` passed 342 checks, 8 of them the `associated:` checks of T1 that cover all 13 member positions on an event and on an alarm with a state; rows `c-associated-switch` and `p-associated-float-print` KILLED by the T1 checks named in `intended` |
| T2 | 2026-11-13T20:08Z | the shipped server and probe on this host | Pass | the same run passed the 34 checks of the 17 rejected-line cases of T2; rows `c-associated-member-any`, `c-associated-sbyte-range`, `c-associated-int16-range`, `c-associated-int32-range`, `c-associated-int64-overflow`, `c-associated-uint16-range`, `c-associated-uint32-range`, `c-associated-uint64-overflow`, `c-associated-float-range`, and `c-associated-finite-off` KILLED by the T2 checks named in `intended` |

Full tables from 2026-11-13T20:08Z to 21:09Z with `--make-var EPICS_TREE=<tree>`: the control run passed all 342 checks. `t/mutations/server.json` (145 rows): 140 rows KILLED and 5 EQUIVALENT, none CHECK, SURVIVED, or INCOMPLETE; seven rows (`c-field-event-fields-off`, `c-field-key-slash-off`, `c-field-stateful-write-off`, `c-field-value-first-word`, `c-retain-false`, `c-stop-exit-failure`, `p-events-fields-off`) also fail checks of T1, which were added to their `intended` lists, and were run again alone and KILLED. `t/mutations/tools.json` (16 rows): 16 KILLED. The sources and tests were not changed between the start of the run and its end.

##### Closure Evidence

- Landed: commits `500b1576566c97b68f4eb4e86d23119c5dbeefea` and `799dd1b135f5f32b473050684ff569aa1449d964` pushed to `origin/master`. After `git fetch`, `git rev-parse HEAD origin/master` printed `799dd1b135f5f32b473050684ff569aa1449d964` twice, observed 2026-11-13T21:14Z.
- Linked issue #2: the body was edited to the shipped state, a closing comment was posted, and the issue was closed with reason `completed`. `gh issue view 2 --repo jeonghanlee/opcua-server-sim` printed state `CLOSED`, state reason `COMPLETED`, closed at 2026-11-13T21:18:50Z.

#### M9 - GoodOverload and registered nodes

Origin: ef67f5e / M9
Identity History: none
GitHub Issue: #3 https://github.com/jeonghanlee/opcua-server-sim/issues/3
Status: Blocked

##### Summary

The imitated server reports the status `GoodOverload` when sampling is late, and answers a request to register nodes with numeric identifiers while a registered node above the configured maximum keeps its string identifier. The owner selected these items as hard ones (D5).

Premise, read 2026-11-12 in the open62541 sources: the symbol `GOODOVERLOAD` does not occur, and the service function for registering nodes (`Service_RegisterNodes` in `src/server/ua_services_view.c`) only checks the count limit and returns the given identifiers. The library has no hook for either behavior.

##### Scope

Both items, built the way G4 decides, or retired by that decision.

Out of scope: Any change to the library that the decision of G4 does not name.

##### Completion Criteria

- Per the decision of G4: the observed results of T1 and T2, or the retirement recorded in Closure Evidence with its decision date.

##### Dependencies And Decisions

- M8 (work ordering set by D5)
- G4 (how to build the items); resume as Not started

##### Implementation Plan

Plan Status: draft
Plan Acceptance: none
Implementation Authorization: none
Superseded Plan Artifacts: none

1. Apply the decision of G4.
2. If the decision is a library patch: write the patch for registered nodes and for the late sampling status, carry it through the wrapper, and add tests.
3. If the decision is retirement: record it in Closure Evidence and keep the rows in the table of `docs/references.md` that lists documented behavior without a counterpart.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| T1 | Integration | Register string node ids through the probe client and read through the returned ids; register more nodes than the configured maximum | the shipped server and probe | the ids are numeric up to the maximum, the rest keep their string ids, and reads through the returned ids succeed; a copy that returns every id unchanged must fail this check |
| T2 | Integration | Subscribe with a sampling interval the server cannot keep under load | the shipped server and probe | the data change notification carries the status `GoodOverload`; a copy that never sets it must fail this check |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| T1 | Not run | the shipped server and probe | Pending | none |
| T2 | Not run | the shipped server and probe | Pending | none |

##### Closure Evidence

- none

#### M3 - Technical documentation

Origin: ef67f5e / M3
Identity History: none
GitHub Issue: #4 https://github.com/jeonghanlee/opcua-server-sim/issues/4
Status: Complete

##### Summary

A documentation book for the simulator: what it is, how to build, run, and verify it, and the exact values of its configuration, model description, and simulation file. The reader is a controls engineer who knows EPICS and Linux and does not know open62541 or the OPC UA model of a Siemens S7-1500 (D11).

##### Scope

- Concept pages: purpose, architecture, the model and the simulation file.
- Procedure pages: build, run, generate the NodeSet, create the certificate, run the tests (including the variable `EPICS_TREE`), and run an IOC against the simulator (`ioc/`, D10).
- Reference pages: simulation file keywords, server configuration keys, model description format, make targets, the model contents, the probe client.
- A tutorial (D6) and a glossary.
- The book layout of the `mdbook` skill: `docs/book.toml`, `docs/src/SUMMARY.md` with `create-missing = false`, the build with the Docker image `jeonghanlee/mdbook`, and `docs/book/` in `.gitignore`.
- The command check `tools/doc-check.pl` that runs the commands of the procedure pages (D9), the make target `book-check` that runs it, and the option `--make-target` of `tools/mutation-check.pl` (default `test`) that runs the fault rows through that target.

Out of scope: Statements about behavior no test or run has observed, and publishing the book to GitHub Pages (decided separately by the owner).

##### Completion Criteria

- Every command in the book ran as shown on a clean checkout.
- The book passed the technical-writing review checklist and a second-person review.

##### Dependencies And Decisions

- G2 (format and tutorial), Complete 2026-11-12 with D6: mdBook, with a tutorial
- D9 (the command check is a Perl tool that runs the commands of the pages)
- D10 (the book has a procedure page for the IOC)
- D11 (the reader of the book)
- D12 (the title and the author of the book)

##### Implementation Plan

Plan Status: accepted
Plan Acceptance: 2026-11-13, with the decisions D9 to D12 accepted by the owner
Implementation Authorization: 2026-11-13 for the plan as accepted (the owner authorized the implementation; commit, push, and the edit of issue #4 are separate)
Superseded Plan Artifacts: none

1. Set up the book layout with the title `opcua-server-sim` and the author `Jeong Han Lee` in `docs/book.toml` (D12), build it with the Docker image, and plan the pages by type (G2, D6, D10). Closed by T3.
2. Write the check design table and the test contract of T1 below before the tool code, then write `tools/doc-check.pl`: it takes the marked commands and expected outputs from the procedure pages, replaces the placeholders from a substitution table whose values it receives at run time, makes a clean checkout of the tree from the files that Git does not ignore (`git ls-files --cached --others --exclude-standard`), runs each command in it, normalizes the volatile text, and compares the exit status and the output with the page (D9). It reads a `bash` code block as a command and the code block without a language that follows it as the output of that command, which is the form of the `technical-writing` skill, and a command that is shown and not run carries a separate mark. It prints TAP with one named check per command and the `Files=` and `Tests=` summary of `prove`, because `tools/mutation-check.pl` reads the failed check names and the summary from that output. Closed by T1.
3. Write the pages from the code, the shipped model files, and observed output, with the commands and outputs in the code blocks that the tool reads. Closed by T1 and T3.
4. Add the make target `book-check` and the option `--make-target` of `tools/mutation-check.pl`, add the fault rows of T1 (a changed command, a changed output, a placeholder left unreplaced), and run them with `tools/mutation-check.pl --make-target book-check`. The target `book-check` runs the check through `prove` and is not a part of `make test`, because the page of the tests runs `make test` and would start the check again. Closed by T1 and the proving rule under the Test Plan of M1.
5. Run the review passes of T2 and T4 and correct the findings. Closed by T2 and T4.

Page plan (paths under `docs/src/`; the type and the title form follow the `technical-writing` skill):

| Page | Type | Title |
| --- | --- | --- |
| `introduction.md` | Concept | The purpose of opcua-server-sim |
| `tutorial.md` | Tutorial | Build the simulator and read a tag with the probe |
| `concepts/purpose.md` | Concept | The reasons for imitating an S7-1500 |
| `concepts/architecture.md` | Concept | The architecture of the simulator |
| `concepts/model.md` | Concept | The composite model of the simulator |
| `concepts/simulation-file.md` | Concept | The role of a simulation file in the server |
| `procedures/build.md` | Procedure | Build the server and the probe |
| `procedures/certificate.md` | Procedure | Create the server certificate |
| `procedures/nodeset.md` | Procedure | Generate the NodeSet of a model |
| `procedures/run.md` | Procedure | Run the simulator |
| `procedures/test.md` | Procedure | Run the tests |
| `procedures/ioc.md` | Procedure | Run an IOC against the simulator |
| `reference/simulation-keywords.md` | Reference | Simulation file keywords |
| `reference/server-config.md` | Reference | Server configuration keys |
| `reference/model-description.md` | Reference | Model description format |
| `reference/make.md` | Reference | Make targets and variables |
| `reference/model-contents.md` | Reference | Contents of the composite model |
| `reference/probe.md` | Reference | Probe client commands |
| `glossary.md` | Reference | Glossary of terms used in the book |

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| T1 | Documentation | `tools/doc-check.pl` runs every marked command of every procedure page in a clean checkout of the tree with the values of the substitution table and compares the exit status and the normalized output with the page | a clean checkout of the tree on this host; the substitution table names the library install path, the UA-Nodeset path, and the EPICS tree, and its values are given when the check runs | each command succeeds and prints what the page states; a copy with a changed command, a copy with a changed stated output, and a copy with a placeholder left unreplaced must each fail this check for that reason |
| T2 | Review | Second-person pass over every page from the seat of the reader named in the Summary (D11), run by a fresh sub-agent | the finished book | no finding above the severity floor |
| T3 | Documentation | Build the book with the Docker image `jeonghanlee/mdbook`, and keep the output of `mdbook --version` | the finished book | `docs/book/index.html` and every page linked from `SUMMARY.md` exist, every `.md` file of `docs/src/` except `SUMMARY.md` has its `.html` in `docs/book/`, and the sources are unchanged by the build; a copy whose `SUMMARY.md` links a page that does not exist and a copy with a page file that `SUMMARY.md` does not link must each fail this check |
| T4 | Review | Third-person pass over every page against the ten items of the review checklist of the `technical-writing` skill, run by a fresh sub-agent, by execution where an item can be counted (words of a heading, words of a sentence, reachability from `SUMMARY.md`) | the finished book | every item passes for every page |

Contract of T1: the objective is that the commands and outputs the book states are the ones the shipped tree produces. The target is the shipped tools (`make`, the server, the probe, the IOC test) in a clean checkout of the tree, which the check makes itself from the files that Git does not ignore, so that a local setting or a build output of the working tree cannot make a command pass. Each command keeps its exit status, its output bytes, and the SHA-256 of the page and of the tool. The substitution table is part of the check and not of the page text; the repository holds only the names of the placeholders, such as `<open62541_install_path>`, and the values come from options or environment variables when the check runs, because the repository is public and the values are paths of this host. Timestamps, process ids, ports, hashes, modification times, elapsed and CPU times, and the absolute path of the checkout are normalized before the comparison and everything else must match. A page states a line that does not change when a test is added, such as `Result: PASS`, and not the number of checks. A run of `make test` takes about two minutes, so the fault series declares the number of rows that run at once. The check prints one named check per command in TAP and the `Files=` and `Tests=` summary of `prove`, which is the output that `tools/mutation-check.pl` reads. The diagnostic lines of a failed check go to standard error, as `Test::More` prints them, so that `prove` shows them. A command that does not end by itself, such as the server of `make run` or an IOC at its prompt, is started in the background, the check waits for the readiness text of its expected output, runs the commands that follow, and stops it with INT; a command that cannot be checked this way is listed as unproven. A missing prerequisite makes a cell Incomplete and not Failed. The setup of a page comes from `make` called directly and not from the commands of the page, so a changed command of a page cannot stop the setup; a check that no setup can reach without that command is listed as unproven. The coverage is each page, its commands, and the three kinds of fault; a cell skipped for a missing EPICS tree is listed as skipped. A run uses the pages and the tool with the recorded SHA-256, and a changed page is run again.

Check design of T1 (the checks share one run of the tool, and every page runs in its own clean checkout):

| Check | Claim and the clause it comes from | Inputs and their distance from the boundary | State read and the step that sets it | Expected value and its condition |
| --- | --- | --- | --- | --- |
| command result | A command of a page exits 0 and prints what the page states (Completion Criteria of this work; the `technical-writing` rule that every shown command ran as shown) | The command and the output block of the page; a fault copy changes one word of the command or one word of the output, outside the normalized forms | The clean checkout, made by the check from the files that Git does not ignore at the start of each page; the values from the environment | The output block of the page with the placeholders replaced and the volatile text normalized on both sides; holds for output that has no text outside the normalization rules |
| placeholder | No placeholder is left unreplaced (the `technical-writing` rule that a command runs as shown once each placeholder is replaced) | The placeholder names of a page against the names that have a value; a fault copy uses a name without a value | The values from the environment, set by the target `book-check` | Every name has a value; the check fails and names the placeholder otherwise |
| background command | A command that does not end by itself reaches its ready text and stops on INT (plan of this work) | The ready text of the mark of the page; the wait has a declared bound | The process started by the check and stopped by the check at the end of the page | The ready text appears within the bound, and the process ends after INT |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| T1 | 2026-11-14T09:59Z | clean checkouts of the tree on this host | Passed | `make book-check` ran 38 checks, `Result: PASS`; fault rows through `tools/mutation-check.pl --make-target book-check` for `procedures/test.md` (8 rows) and for samples of `procedures/build.md`, `tutorial.md`, and `procedures/ioc.md` (8 rows) were all KILLED, with a changed command, a changed output, and a placeholder left unreplaced among them |
| T2 | 2026-11-14T05:24Z | the finished book | Passed | the second-person passes ended with pass 18 and no finding above the severity floor; the corrections are in the pages of the commit that holds the book |
| T3 | 2026-11-14T09:54Z | the finished book, Docker image `jeonghanlee/mdbook`, `mdbook v0.5.4` | Passed | On a copy of the tree: build exit 0, sources unchanged, `docs/book/index.html` and the `.html` of all 19 pages exist, every page linked from `SUMMARY.md` has its `.html`. A copy whose `SUMMARY.md` links a missing page failed, and a copy with an unlinked page file failed (no `.html` for it) |
| T4 | 2026-11-14T04:49Z | the finished book | Passed | the third-person passes ended with pass 16 and no finding above the severity floor; the corrections are in the pages of the commit that holds the book |

##### Closure Evidence

- Landed: commits `c9d9dadd3676907fc34f7f3a7dbed631611e69cc` (book), `141b574` (command check), `627a7b7` (diagnostics on standard error), `adb4829` (key generation), `b35f292` (skipped-test detection), and `75884c5` (work register) pushed to `origin/master`. After `git fetch`, `git rev-parse --short HEAD origin/master` printed `75884c5` twice, no outgoing or incoming commit, and `git diff --stat origin/master HEAD` over `docs/src`, `docs/book.toml`, `tools`, `t`, `configure`, and `.gitignore` printed nothing, observed 2026-11-14T18:57Z.
- Linked issue #4: the body was edited to the shipped state, a closing comment was posted, and the issue was closed with reason `completed`. `gh issue view 4 --repo jeonghanlee/opcua-server-sim` printed state `CLOSED`, state reason `COMPLETED`, closed at 2026-11-14T18:57:02Z.
- Not run: the fault rows of the blocks of each page that the T1 row does not name.
- Found during the check: `openssl genpkey -quiet` fails on OpenSSL 1.1.1; removed from `configure/RULES_BUILD` and `t/server.t` (adb4829).
- Found during the check: `prove` hides `#` lines on standard output, so `tools/doc-check.pl` prints failure diagnostics on standard error.
- Found during the check: `tools/mutation-check.pl` took the text `skipped:` in a check name for a skipped test; it now reads only the summary line of `prove`.

#### M4 - Container image

Origin: ef67f5e / M4
Identity History: none
GitHub Issue: #5 https://github.com/jeonghanlee/opcua-server-sim/issues/5
Status: Blocked

##### Summary

A container image that holds the server, the probe client, and the composite model, and starts the server on the default port.

##### Scope

- A Dockerfile that builds open62541 through the wrapper, builds the server and the probe, and creates the certificate at image build or first start.
- A start command equivalent to `make run`.

Out of scope: Publishing the image to a registry unless G3 records the owner's approval.

##### Completion Criteria

- The image builds from a clean context.
- A container started from it answers a probe read of `ns=3;s=OperatingMode` with `Good 8`.

##### Dependencies And Decisions

- G1 (wrapper changes committed); resume as Not started
- G3 (Dockerfile location and publication); resume as Not started
- D2 (the wrapper provides the open62541 build requirements)
- D13 (the branch `open62541-1.5` of the wrapper carries open62541 1.5.10)

##### Implementation Plan

Plan Status: draft
Plan Acceptance: none
Implementation Authorization: none
Superseded Plan Artifacts: none

1. Write the Dockerfile at the location G3 records.
2. Build the image and start a container with the port published.
3. Run the probe client against the container.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| T1 | Build | Build the image from a clean context | container host | the build succeeds; a copy of the Dockerfile with a wrong source path must fail this check |
| T2 | Integration | Start a container and run `opcua-probe` read of `ns=3;s=OperatingMode` from the host | container host | the output is `Good 8`; an image built with a wrong model path must fail this check |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| T1 | Not run | container host | Pending | none |
| T2 | Not run | container host | Pending | none |

##### Closure Evidence

- none

#### G2 - Owner decides the documentation format and the tutorial

Origin: ef67f5e / G2
GitHub Issue: none
Status: Complete

##### Summary

The owner chooses the book format (for example mdBook) and whether the book has a tutorial or records why it skips one. This gates M3.

##### Completion Criteria

- Both choices are recorded in Decisions with a decision date.

##### Verification Results

| Observed At | Result | Evidence |
| --- | --- | --- |
| 2026-11-13T02:40Z | Passed | Decision D6 of 2026-11-12 records mdBook as the format and a tutorial in the book |

##### Closure Evidence

- Decision D6, 2026-11-12: the book is an mdBook book and has a tutorial.

#### G1 - open62541-env changes committed

Origin: ef67f5e / G1
GitHub Issue: none
Status: Open

##### Summary

The open62541-env repository holds uncommitted changes that `make open62541` needs: the `CMAKE_EXTRA_OPTIONS` support in `configure/CONFIG_SITE` and `configure/RULES_INSTALL`, and `patch/1.5.10.p0.patch`. The owner commits them on the branch `open62541-1.5` of that repository (D13); its master branch stays on open62541 1.3.15. This gates M4.

##### Completion Criteria

- `git status` of the open62541-env repository shows those paths committed on the branch `open62541-1.5`, and its master branch is unchanged.

##### Verification Results

| Observed At | Result | Evidence |
| --- | --- | --- |
| Not run | Pending | `git -C <open62541-env path> status --short` and `git -C <open62541-env path> log --oneline master..open62541-1.5` |

##### Closure Evidence

- none

#### G3 - Owner decides the Dockerfile location and the image publication

Origin: ef67f5e / G3
GitHub Issue: none
Status: Open

##### Summary

The owner chooses whether the Dockerfile lives in this repository or in the repository of the container image Dockerfiles, and whether an image may be published. This gates M4.

##### Completion Criteria

- Both choices are recorded in Decisions with a decision date.

##### Verification Results

| Observed At | Result | Evidence |
| --- | --- | --- |
| Not run | Pending | decision date |

##### Closure Evidence

- none

#### G4 - Owner decides how to build GoodOverload and registered nodes

Origin: ef67f5e / G4
GitHub Issue: none
Status: Open

##### Summary

The library offers no hook for `GoodOverload` or for numeric registered node identifiers. The owner chooses between a patch of open62541 carried through the wrapper (the wrapper already carries one patch, for the NodeSet loader; a patch needs maintenance at every library update) and retiring both items. This gates M9.

##### Completion Criteria

- The choice is recorded in Decisions with a decision date.

##### Verification Results

| Observed At | Result | Evidence |
| --- | --- | --- |
| Not run | Pending | decision date |

##### Closure Evidence

- none

## Backlog

Backlog rows are unassigned, use the same schema, and are excluded from the release tally. At reset, rebuild this section from surviving work and assign new local IDs.

### Work

| Group | ID | Work unit | Type | Status | Ready | Deps | Done when / Evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Verify | M5 | Third-person review of the corrected tree | Milestone | Open | No | | Open until the owner assigns it (named condition, 2026-11-12); [detail](#m5---third-person-review-of-the-corrected-tree) |
| Verify | M6 | Verify ConditionRefresh and alarm behavior while the CPU is in STOP | Milestone | Open | No | | Open until the owner assigns it (named condition, 2026-11-12); [detail](#m6---verify-conditionrefresh-and-alarm-behavior-while-the-cpu-is-in-stop) |
| Deliver | M7 | Commit the working tree | Milestone | Complete | No | | `git status` shows a clean tree and the commit messages follow the repository rules, observed 2026-11-15; [detail](#m7---commit-the-working-tree) |

### Backlog Details

#### M5 - Third-person review of the corrected tree

Origin: ef67f5e / M5
Identity History: none
GitHub Issue: none
Status: Open

##### Summary

The first third-person review of the tree reported one must-fix finding and eight minor findings. All were corrected or settled by owner decision. A second pass checks the corrected tree.

##### Scope

A full read of the sources, the build configuration, the model files, and `docs/references.md`, with an execution check of every claim.

Out of scope: Changes to the tree; findings go to the owner.

##### Completion Criteria

- The pass reports no finding above the severity floor, or the owner closes the loop.

##### Dependencies And Decisions

- none

##### Implementation Plan

Plan Status: draft
Plan Acceptance: none
Implementation Authorization: none
Superseded Plan Artifacts: none

1. Freeze the review charter for the corrected tree.
2. Run the pass and report the findings.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| T1 | Review | Third-person pass with execution checks | the working tree | no finding above the severity floor |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| T1 | Not run | the working tree | Pending | none |

##### Closure Evidence

- none

#### M6 - Verify ConditionRefresh and alarm behavior while the CPU is in STOP

Origin: ef67f5e / M6
Identity History: none
GitHub Issue: none
Status: Open

##### Summary

Two alarm behaviors have no test: the method `ConditionRefresh`, and the reporting of alarms while the simulated CPU is in STOP. The server evaluates alarm triggers only in RUN.

##### Scope

Tests in `t/server.t` for both behaviors, and a documented decision on the STOP behavior when the sources do not state it.

Out of scope: New alarm kinds.

##### Completion Criteria

- Observed results of both behaviors are recorded and covered by tests.

##### Dependencies And Decisions

- none

##### Implementation Plan

Plan Status: draft
Plan Acceptance: none
Implementation Authorization: none
Superseded Plan Artifacts: none

1. Add a `ConditionRefresh` call to the probe client and a test that follows an active alarm.
2. Observe alarms raised during STOP and after RUN and record the behavior.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| T1 | Integration | Call `ConditionRefresh` with an active alarm through the probe client | the shipped server and probe | the active alarm is reported again |
| T2 | Integration | Raise an alarm trigger while the CPU is in STOP, then switch to RUN | the shipped server and probe | the observed events match the decision recorded for this behavior |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| T1 | Not run | the shipped server and probe | Pending | none |
| T2 | Not run | the shipped server and probe | Pending | none |

##### Closure Evidence

- none

#### M7 - Commit the working tree

Origin: ef67f5e / M7
Identity History: none
GitHub Issue: none
Status: Complete

##### Summary

The repository holds one commit and every file of the simulator is untracked. The work needs commits in logical units. A commit needs the owner's separate commit delegation.

##### Scope

Commits of the server source, the tools and tests, the build configuration, the models, and the documents.

Out of scope: Push, tags, and releases.

##### Completion Criteria

- `git status` shows a clean tree and the commit messages follow the repository rules.

##### Dependencies And Decisions

- none

##### Implementation Plan

Plan Status: draft
Plan Acceptance: none
Implementation Authorization: none
Superseded Plan Artifacts: none

1. Group the files into logical commits and show each message first.
2. Commit each group after the owner's delegation.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| T1 | Repository | `git status` after the last commit | the repository | no untracked or modified files |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| T1 | 2026-11-15 | the repository | Passed | `git -C <repository path> status --short` printed no line; the tree has 69 tracked files and 25 commits |

##### Closure Evidence

- The commits were made by the owner or under the owner's commit delegation, and they are on `origin/master`, so the condition of the row is met on 2026-11-15.
