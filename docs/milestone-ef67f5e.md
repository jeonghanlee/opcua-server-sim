# Work Register

Release line: master
Milestone index: ef67f5e
Canonical path: `docs/milestone-ef67f5e.md`
Canonical branch or ref: master
Git upstream: origin/master
Remote tracker: jeonghanlee/opcua-server-sim (no GitHub milestone)

Next session entry point: M2 is Complete. M1, M3, and M8 are Ready; each needs plan review, plan acceptance, and implementation authorization first.

## Milestone

### Work

| Group | ID | Work unit | Type | Status | Ready | Deps | Done when / Evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Verify | M1 | IOC verification | Milestone | Not started | Yes | | An EPICS IOC reads and writes the tags of the composite model and the checks T1 to T6 pass; [detail](#m1---ioc-verification) |
| Build | M2 | Simulator completeness | Milestone | Complete | No | D5 | The small and medium items of the owner's selection are built and tested by T1 to T9; [detail](#m2---simulator-completeness) |
| Build | M8 | Alarm associated values | Milestone | Not started | Yes | M2 | Events carry `AssociatedValue_01` to `AssociatedValue_10` as the union type, shown by T1; [detail](#m8---alarm-associated-values) |
| Build | M9 | GoodOverload and registered nodes | Milestone | Blocked | No | M8, G4 | Each item is built and shown by T1 and T2, or retired by the decision of G4; [detail](#m9---goodoverload-and-registered-nodes) |
| Document | M3 | Technical documentation | Milestone | Not started | Yes | G2, D6 | The documentation book exists, every command in it ran as shown, and it passed second-person review; [detail](#m3---technical-documentation) |
| Deliver | M4 | Container image | Milestone | Blocked | No | G1, G3, D2 | A container image runs the server with the composite model and answers a probe read; [detail](#m4---container-image) |
| Document | G2 | Owner decides the documentation format and the tutorial | External gate | Complete | No | | The owner records both choices in Decisions; [detail](#g2---owner-decides-the-documentation-format-and-the-tutorial) |
| Deliver | G1 | open62541-env changes committed | External gate | Open | No | | The wrapper changes are committed in the open62541-env repository; [detail](#g1---open62541-env-changes-committed) |
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

### Milestone Details

#### M1 - IOC verification

Origin: ef67f5e / M1
Identity History: none
GitHub Issue: none
Status: Not started

##### Summary

The server was built to serve an EPICS IOC that uses the opcua module. The composite model has not been exercised with such an IOC. This work connects an IOC to the running server and checks what the module reads and writes.

##### Scope

- An IOC database and startup script for the composite model, kept where M1 step 1 decides.
- Reads and writes of scalar tags, one structure with a nested structure, and arrays.
- Subscription updates of simulated values, the CPU RUN and STOP switch, and one secured session with a user account.
- A method call, when the opcua module version in use supports method calls.

Out of scope: Alarms and Conditions (the module does not subscribe to events), changes to the server behavior, and the IOC repository of any site.

##### Completion Criteria

- Checks T1 to T6 have observed results recorded in Verification Results.
- A defect the IOC reveals is recorded as a new row or fixed under M2 before this work completes.

##### Dependencies And Decisions

- none

##### Implementation Plan

Plan Status: draft
Plan Acceptance: none
Implementation Authorization: none
Superseded Plan Artifacts: none

1. Choose the IOC directory and write the startup script for the opcua module and the session settings.
2. Write the database for scalar tags of `DataStatic` and `DataSimulation`.
3. Add the structure `myUdt`, the arrays, and the switch `ns=4;s=Simulator.Run`.
4. Add the secured session settings with the account of `simulation.conf`.
5. Run T1 to T6 and record the observed results.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| T1 | Integration | Start `make run`; start the IOC; read the start values of `DataStatic` scalar tags | server and IOC on one host | the IOC reports the start values of the model; a copy of the tree with `myInt` start value 43 must fail this check |
| T2 | Integration | Read and write the whole structure `myUdt` and its member `udtTime` | server and IOC on one host | values read and written match in both directions; a copy with member-to-structure propagation off must fail this check |
| T3 | Integration | Read and write `myArrayInt` and one element | server and IOC on one host | the array and its element agree after a write; the same copy must fail this check |
| T4 | Integration | Watch `Clock_Byte` and `DataSimulation` values through subscriptions | server and IOC on one host | the IOC records value changes without polling; a copy whose `pack` writes nothing must fail this check |
| T5 | Integration | Write the switch `Simulator.Run` false and true | server and IOC on one host | the operating mode record shows 4 and then 8 and values return to their start values; a copy that does not restore start values must fail this check |
| T6 | Integration | Connect with a secured session and the account of the simulation file | server and IOC on one host | the session opens and a read succeeds; a copy with a wrong password for the account must fail this check |

Proving rule for M1 to M4, M8, and M9: before a check is relied on, the fault named in its row is applied to a scratch copy of the tree (`~/.claude/skills/test-framework/scripts/build-mutants.py`), the unchanged tree is run through the same entry point first and must pass every check, and the check must fail for the named reason. A check without a run of its fault row is unproven.

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| T1 | Not run | server and IOC on one host | Pending | none |
| T2 | Not run | server and IOC on one host | Pending | none |
| T3 | Not run | server and IOC on one host | Pending | none |
| T4 | Not run | server and IOC on one host | Pending | none |
| T5 | Not run | server and IOC on one host | Pending | none |
| T6 | Not run | server and IOC on one host | Pending | none |

##### Closure Evidence

- none

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
GitHub Issue: none
Status: Not started

##### Summary

An alarm event carries up to ten associated values, `AssociatedValue_01` to `AssociatedValue_10`, of the union type `SimaticAssociatedAlarmValue` (`ns=3;i=1809`, encoding `ns=3;i=1810` in the model). The server publishes none. The owner selected this item as a hard one (D5).

Premise, read 2026-11-12 in the open62541 sources: the NodeSet loader turns a data type definition with `IsUnion` into a union data type (`DataTypeImporter.c` of the nodesetLoader backend). Hypothesis: the union defined in `nodeset/alarms.xml` is registered with the member order that gives the switch values of the manual (Boolean 2, Int16 3, Int32 4, SByte 6, Byte 7, UInt16 8, Float 11, Double 12, UInt32 9, String 13). The first step checks it.

##### Scope

Setting associated values of an alarm and an event from the simulation file, and publishing them as the union in the event fields.

Out of scope: The text placeholders that clients resolve in the alarm message.

##### Completion Criteria

- An event carries associated values whose switch field and member match the example of the manual.

##### Dependencies And Decisions

- M2 (work ordering set by D5)

##### Implementation Plan

Plan Status: draft
Plan Acceptance: none
Implementation Authorization: none
Superseded Plan Artifacts: none

1. Check that the union data type of the model is registered and encodes to the expected switch values; if it is not, register it from its definition at start.
2. Extend the `field` keyword of M2 step 3 to associated values.
3. Extend the probe client to print an associated value.
4. Add the test.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| T1 | Integration | Raise an alarm with associated values of several member types and subscribe through the probe | the shipped server and probe | each event field shows the switch value and the member value that was configured; a copy that writes a wrong switch value must fail this check |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| T1 | Not run | the shipped server and probe | Pending | none |

##### Closure Evidence

- none

#### M9 - GoodOverload and registered nodes

Origin: ef67f5e / M9
Identity History: none
GitHub Issue: none
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
GitHub Issue: none
Status: Not started

##### Summary

A documentation book for the simulator: what it is, how to build, run, and verify it, and the exact values of its configuration, model description, and simulation file.

##### Scope

- Concept pages: purpose, architecture, the model and the simulation file.
- Procedure pages: build, run, generate the NodeSet, create the certificate, run the tests.
- Reference pages: simulation file keywords, server configuration keys, model description format, make targets, the model contents, the probe client.
- A glossary, and the tutorial when G2 decides to include one.

Out of scope: Statements about behavior no test or run has observed.

##### Completion Criteria

- Every command in the book ran as shown on a clean checkout.
- The book passed the technical-writing review checklist and a second-person review.

##### Dependencies And Decisions

- G2 (format and tutorial), Complete 2026-11-12 with D6: mdBook, with a tutorial

##### Implementation Plan

Plan Status: draft
Plan Acceptance: none
Implementation Authorization: none
Superseded Plan Artifacts: none

1. Apply the format and tutorial decisions of G2 and plan the pages by type.
2. Write the pages from the code, the shipped model files, and observed output.
3. Run every command shown and replace placeholders with real values.
4. Run the review passes and correct the findings.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| T1 | Documentation | Run every command of every procedure page as shown | clean checkout of the tree | each command succeeds and prints what the page states; a page whose command or stated output is altered in a scratch copy must fail this check |
| T2 | Review | Second-person pass over every page from the seat of the reader | the finished book | no finding above the severity floor; a seeded defect in a scratch copy of one page must be found by the pass |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| T1 | Not run | clean checkout of the tree | Pending | none |
| T2 | Not run | the finished book | Pending | none |

##### Closure Evidence

- none

#### M4 - Container image

Origin: ef67f5e / M4
Identity History: none
GitHub Issue: none
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

The open62541-env repository holds uncommitted changes that `make open62541` needs: the `CMAKE_EXTRA_OPTIONS` support in `configure/CONFIG_SITE` and `configure/RULES_INSTALL`, and `patch/1.5.10.p0.patch`. The owner commits them there. This gates M4.

##### Completion Criteria

- `git status` of the open62541-env repository shows those paths committed.

##### Verification Results

| Observed At | Result | Evidence |
| --- | --- | --- |
| Not run | Pending | `git -C <open62541-env path> status --short` |

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
| Deliver | M7 | Commit the working tree | Milestone | Open | No | | Open until the owner delegates commits (named condition, 2026-11-12); [detail](#m7---commit-the-working-tree) |

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
Status: Open

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
| T1 | Not run | the repository | Pending | none |

##### Closure Evidence

- none
