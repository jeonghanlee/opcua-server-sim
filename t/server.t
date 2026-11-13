#!/usr/bin/env perl
#
# Integration test of the server with the composite model. The test starts the
# built server with the shipped configuration, simulation file, and NodeSets,
# and checks it over TCP with the built opcua-probe client. Only the port is
# replaced, in a copy of the server configuration. "make test" builds the
# binaries and names them in SIM_SERVER, SIM_PROBE, and SIM_DI.

use strict;
use warnings;

use Cwd qw(abs_path);
use File::Basename qw(dirname);
use File::Spec;
use File::Temp qw(tempdir);
use IO::Socket::INET;
use POSIX ();
use Test::More;
use Time::HiRes qw(sleep time);

my ($SERVER, $PROBE, $DI) = @ENV{qw(SIM_SERVER SIM_PROBE SIM_DI)};
plan skip_all => 'run "make test": SIM_SERVER, SIM_PROBE, and SIM_DI name the built binaries and the DI NodeSet'
    if !defined $SERVER || !defined $PROBE || !defined $DI || !-x $SERVER || !-x $PROBE || !-f $DI;

my $TOP   = abs_path(File::Spec->catdir(dirname(__FILE__), File::Spec->updir));
my $MODEL = File::Spec->catdir($TOP, 'models', 's7-1500-composite');
my $NODESET    = File::Spec->catfile($MODEL, 's7-1500-composite.NodeSet2.xml');
my $SIMULATION = File::Spec->catfile($MODEL, 'simulation.conf');
plan skip_all => 'run "make certificate": the server certificate of the model is missing'
    if !-f File::Spec->catfile($MODEL, 'pki', 'server-cert.der');

# Limits of the test: seconds to wait for the server to answer, for an event,
# and for one probe command.
my $START_SECONDS   = 20;
my $EVENT_SECONDS   = 20;
my $COMMAND_SECONDS = 30;

# Node ids of the composite model and the simulator control node.
my $RUN_SWITCH = 'ns=4;s=Simulator.Run';
my $MODE       = 'ns=3;s=OperatingMode';
my $ADDING     = 'ns=3;s="InstUaMethodAdding"';
my $SORT       = 'ns=3;s="InstMethodSort"';
my $STATE      = 'ns=3;s="InstMethodSequence"';
my $TIMER      = 'ns=3;s="IEC_Timer_0_DB"';
my $TRIGGER    = 'ns=3;s="AlarmTriggers"."Program_Alarm_2"';
my $NOTIFIER   = 'ns=3;s=SimaticAlarmsAndConditions';
my $ACKNOWLEDGE = 'i=9111';

my $dir = tempdir(CLEANUP => 1);
my @servers;
END {
    for my $pid (@servers) {
        kill 'INT', $pid;
        waitpid($pid, 0);
    }
}

sub free_port {
    my $socket = IO::Socket::INET->new(Listen => 1, LocalAddr => '127.0.0.1', LocalPort => 0, Proto => 'tcp')
        or die "free port: $!\n";
    my $port = $socket->sockport;
    close($socket);
    return $port;
}

sub slurp {
    my ($path) = @_;
    open(my $fh, '<:raw', $path) or die "$path: $!\n";
    local $/;
    my $data = <$fh>;
    close($fh) or die "$path: $!\n";
    return $data;
}

sub spew {
    my ($path, $data) = @_;
    open(my $fh, '>:raw', $path) or die "$path: $!\n";
    print {$fh} $data or die "$path: $!\n";
    close($fh) or die "$path: $!\n";
    return;
}

# Runs the probe client against a port and returns the exit status and the
# standard output.
sub run_probe {
    my ($port, $options, @args) = @_;
    my $pid = open(my $out, '-|');
    defined $pid or die "fork: $!\n";
    if (!$pid) {
        open(STDERR, '>', File::Spec->devnull) or POSIX::_exit(126);
        alarm $COMMAND_SECONDS;
        { exec { $PROBE } $PROBE, @{$options}, "opc.tcp://localhost:$port", @args; }
        POSIX::_exit(127);
    }
    my $stdout = do { local $/; <$out> };
    close($out);
    my $status = ($? & 127) ? 'signal ' . ($? & 127) : $? >> 8;
    return ($status, defined $stdout ? $stdout : '');
}

# Reads a Variable and returns the status word and the value as one line.
sub read_node {
    my ($port, $node, @options) = @_;
    my (undef, $out) = run_probe($port, \@options, 'read', $node);
    chomp $out;
    return $out;
}

sub write_node {
    my ($port, $node, $type, $value) = @_;
    my (undef, $out) = run_probe($port, [], 'write', $node, $type, $value);
    chomp $out;
    return $out;
}

# Calls a Method and returns the status word and the output lines.
sub call_method {
    my ($port, $object, $method, @arguments) = @_;
    my (undef, $out) = run_probe($port, [], 'call', $object, $method, @arguments);
    my @lines = split /\n/, $out;
    return (shift(@lines) // '', @lines);
}

# Starts the server in the model directory with the given simulation file and
# configuration text. Returns the process id, the port, and the log path.
sub start_server {
    my ($simulation, $config_text) = @_;
    my $port = free_port();
    my $config = File::Spec->catfile($dir, "server-$port.json5");
    my $log    = File::Spec->catfile($dir, "server-$port.log");
    (my $text = $config_text) =~ s{opc\.tcp://:4840}{opc.tcp://:$port};
    spew($config, $text);
    my $pid = fork();
    defined $pid or die "fork: $!\n";
    if (!$pid) {
        chdir $MODEL or POSIX::_exit(126);
        open(STDOUT, '>', $log) or POSIX::_exit(126);
        open(STDERR, '>&', \*STDOUT) or POSIX::_exit(126);
        { exec { $SERVER } $SERVER, '-s', $simulation, $config, $DI, $NODESET; }
        POSIX::_exit(127);
    }
    push @servers, $pid;
    my $deadline = time + $START_SECONDS;
    while (time < $deadline) {
        last if waitpid($pid, POSIX::WNOHANG()) != 0;
        return ($pid, $port, $log) if read_node($port, $MODE) =~ /^Good /;
        sleep 0.3;
    }
    return ($pid, $port, $log);
}

# Stops a started server and returns its exit status.
sub stop_server {
    my ($pid) = @_;
    kill 'INT', $pid;
    waitpid($pid, 0);
    @servers = grep { $_ != $pid } @servers;
    return ($? & 127) ? 'signal ' . ($? & 127) : $? >> 8;
}

# Starts the server and waits for its exit. Returns the exit status and the log.
sub run_failing_server {
    my ($simulation) = @_;
    my $port   = free_port();
    my $log    = File::Spec->catfile($dir, "failing-$port.log");
    my $config = File::Spec->catfile($dir, "failing-$port.json5");
    (my $text = slurp(File::Spec->catfile($MODEL, 'server.json5'))) =~ s{opc\.tcp://:4840}{opc.tcp://:$port};
    spew($config, $text);
    my $pid  = fork();
    defined $pid or die "fork: $!\n";
    if (!$pid) {
        chdir $MODEL or POSIX::_exit(126);
        open(STDOUT, '>', $log) or POSIX::_exit(126);
        open(STDERR, '>&', \*STDOUT) or POSIX::_exit(126);
        alarm $START_SECONDS;
        { exec { $SERVER } $SERVER, '-s', $simulation, $config, $DI, $NODESET; }
        POSIX::_exit(127);
    }
    waitpid($pid, 0);
    my $status = ($? & 127) ? 'signal ' . ($? & 127) : $? >> 8;
    return ($status, slurp($log));
}

# Starts the probe client for events in the background. Returns the process id
# and a handle for its output.
sub start_events {
    my ($port, $node, $seconds, @fields) = @_;
    my $pid = open(my $out, '-|');
    defined $pid or die "fork: $!\n";
    if (!$pid) {
        open(STDERR, '>', File::Spec->devnull) or POSIX::_exit(126);
        { exec { $PROBE } $PROBE, "opc.tcp://localhost:$port", 'events', $node, $seconds, @fields; }
        POSIX::_exit(127);
    }
    return ($pid, $out);
}

# Reads one line from a handle, or undef after the time is up.
sub next_line {
    my ($handle, $seconds) = @_;
    my $line = eval {
        local $SIG{ALRM} = sub { die "timeout\n" };
        alarm $seconds;
        my $text = <$handle>;
        alarm 0;
        $text;
    };
    alarm 0;
    return $line;
}

# Reads a Variable until it shows the expected text or the seconds are up, and
# returns the last text read. A simulation step runs every 50 ms.
sub await_value {
    my ($port, $node, $expected, $seconds) = @_;
    my $deadline = time + ($seconds // 5);
    my $text = read_node($port, $node);
    while ($text ne $expected && time < $deadline) {
        sleep 0.1;
        $text = read_node($port, $node);
    }
    return $text;
}

my $config_text = slurp(File::Spec->catfile($MODEL, 'server.json5'));

# --- The server with the shipped simulation file.
my ($pid, $port, $log) = start_server($SIMULATION, $config_text);
like(read_node($port, $MODE), qr/^Good 8$/, 'start: the CPU is in RUN');
unlike(slurp($log), qr/fatal/, 'start: no fatal message in the log');

my (undef, $endpoints) = run_probe($port, [], 'endpoints');
my @modes = $endpoints =~ /^mode \d policy \S+$/mg;
is(scalar @modes, 11, 'endpoints: eleven');
like($endpoints, qr/^mode 1 policy None$/m, 'endpoints: None');
like($endpoints, qr/^mode 3 policy Aes256_Sha256_RsaPss$/m, 'endpoints: Aes256_Sha256_RsaPss with encryption');

is(read_node($port, 'ns=3;s="DataStatic"."myInt"'), 'Good 42', 'start value: myInt');
is(read_node($port, 'ns=3;s="DataStatic"."myByte"'), 'Good 171', 'start value: myByte');
is(read_node($port, 'ns=3;s="DataStatic"."myWord"'), 'Good 52719', 'start value: myWord');
is(read_node($port, 'ns=3;s="DataStatic"."myUdt"."udtString"'), 'Good "CompositePLC"', 'start value: member of the structure');
is(read_node($port, 'i=2263'), 'Good "opcua-server-sim"', 'BuildInfo: manufacturer');
is(read_node($port, 'i=2261'), 'Good "S7-1500 composite simulator"', 'BuildInfo: product');
is(read_node($port, 'i=11709'), 'Good 1', 'ServerCapabilities: nodes per method call');
is(read_node($port, 'i=2735'), 'Good 5', 'continuation points: browse');
is(read_node($port, 'i=2736'), 'Good 5', 'continuation points: query');
is(read_node($port, 'i=2737'), 'Good 5', 'continuation points: history');

# The alarm of the system diagnostics category reaches its notifier.
{
    my $notifier = 'ns=3;s=SimaticAlarmsAndConditions.SystemDiagnostics';
    my ($events_pid, $events) = start_events($port, $notifier, 8);
    like(next_line($events, $EVENT_SECONDS) // '', qr/^monitor Good$/, 'system diagnostics: subscription accepted');
    is(write_node($port, 'ns=3;s="AlarmTriggers"."System_Alarm"', 'bool', 'true'), 'Good', 'system diagnostics: raise');
    like(next_line($events, $EVENT_SECONDS) // '',
        qr/message="System diagnostics alarm" severity=500 source=SystemDiagnostics active=1 acked=0 retain=1 /,
        'system diagnostics: the notifier reports the alarm');
    is(write_node($port, 'ns=3;s="AlarmTriggers"."System_Alarm"', 'bool', 'false'), 'Good', 'system diagnostics: clear');
    1 while defined next_line($events, $EVENT_SECONDS);
    close($events);
    waitpid($events_pid, 0);
}

# An alarm queue with a limit of 2 and a hysteresis of 1: the third alarm is
# outstanding, and the overload ends only below the limit minus the
# hysteresis.
{
    my $conf = File::Spec->catfile($dir, 'queue.conf');
    spew($conf, "include $SIMULATION\n"
        . "value ns=3;s=SimaticAlarmsAndConditions.ProgramAlarms.MaxAlarmsInQueue 2\n"
        . "value ns=3;s=SimaticAlarmsAndConditions.Overloads.OverloadHysteresis 1\n");
    my ($queue_pid, $queue_port) = start_server($conf, $config_text);
    my @trigger = map { "ns=3;s=\"AlarmTriggers\".\"Program_Alarm_$_\"" } 1 .. 3;
    my $current     = 'ns=3;s=SimaticAlarmsAndConditions.ProgramAlarms.CurrentAlarmsInQueue';
    my $outstanding = 'ns=3;s=SimaticAlarmsAndConditions.Overloads.OutstandingProgramAlarms';
    my $overload    = 'ns=3;s="AlarmTriggers"."Overload_Program"';
    my ($events_pid, $events) = start_events($queue_port, $NOTIFIER, 12);
    like(next_line($events, $EVENT_SECONDS) // '', qr/^monitor Good$/, 'queue: subscription accepted');
    is(read_node($queue_port, $overload), 'Good false', 'queue: no overload at first');
    write_node($queue_port, $trigger[0], 'bool', 'true');
    write_node($queue_port, $trigger[1], 'bool', 'true');
    is(await_value($queue_port, $current, 'Good 2'), 'Good 2', 'queue: two active alarms');
    is(await_value($queue_port, $overload, 'Good true'), 'Good true', 'queue: the overload starts at the limit');
    my $reported = 0;
    for (1 .. 6) {
        my $line = next_line($events, $EVENT_SECONDS) // last;
        $reported = 1 if $line =~ /message="Overload of the program alarms" severity=900 source=ProgramAlarms active=1 /;
        last if $reported;
    }
    ok($reported, 'queue: the overload alarm is reported');
    write_node($queue_port, $trigger[2], 'bool', 'true');
    is(await_value($queue_port, $outstanding, 'Good 1'), 'Good 1', 'queue: the third alarm is outstanding');
    is(read_node($queue_port, $current), 'Good 2', 'queue: the queue holds two alarms');
    write_node($queue_port, $trigger[0], 'bool', 'false');
    is(await_value($queue_port, $outstanding, 'Good 0'), 'Good 0', 'queue: the outstanding alarm becomes active');
    is(read_node($queue_port, $current), 'Good 2', 'queue: the queue is full again');
    is(read_node($queue_port, $overload), 'Good true', 'queue: the overload continues at the limit');
    write_node($queue_port, $trigger[1], 'bool', 'false');
    is(await_value($queue_port, $current, 'Good 1'), 'Good 1', 'queue: one alarm is left');
    sleep 0.4;
    is(read_node($queue_port, $overload), 'Good true', 'queue: the overload continues within the hysteresis');
    write_node($queue_port, $trigger[2], 'bool', 'false');
    is(await_value($queue_port, $current, 'Good 0'), 'Good 0', 'queue: no alarm is left');
    is(await_value($queue_port, $overload, 'Good false'), 'Good false', 'queue: the overload ends below the limit minus the hysteresis');
    kill 'INT', $events_pid;
    close($events);
    waitpid($events_pid, 0);
    is(stop_server($queue_pid), 0, 'queue: the server exits with status 0');
}

# A queue with a limit of 1: two outstanding alarms leave in the order they
# came, an outstanding alarm that goes out is dropped, and the queue of the
# system diagnostics alarms follows the same rules.
{
    my $conf = File::Spec->catfile($dir, 'queue-one.conf');
    spew($conf, "include $SIMULATION\n"
        . "value ns=3;s=SimaticAlarmsAndConditions.ProgramAlarms.MaxAlarmsInQueue 1\n"
        . "value ns=3;s=SimaticAlarmsAndConditions.Overloads.OverloadHysteresis 0\n"
        . "value ns=3;s=SimaticAlarmsAndConditions.SystemDiagnostics.MaxAlarmsInQueue 1\n");
    my ($one_pid, $one_port) = start_server($conf, $config_text);
    my @trigger = map { "ns=3;s=\"AlarmTriggers\".\"Program_Alarm_$_\"" } 1 .. 3;
    my $outstanding = 'ns=3;s=SimaticAlarmsAndConditions.Overloads.OutstandingProgramAlarms';
    my $system      = 'ns=3;s="AlarmTriggers"."System_Alarm"';
    my ($events_pid, $events) = start_events($one_port, $NOTIFIER, 25);
    like(next_line($events, $EVENT_SECONDS) // '', qr/^monitor Good$/, 'queue of one: subscription accepted');
    # Each alarm is seen by a simulation step before the next one is raised, so
    # the order of the outstanding alarms is the order of the writes.
    write_node($one_port, $trigger[0], 'bool', 'true');
    is(await_value($one_port, 'ns=3;s=SimaticAlarmsAndConditions.ProgramAlarms.CurrentAlarmsInQueue', 'Good 1'), 'Good 1',
        'queue of one: the first alarm is active');
    for my $i (1, 2) {
        write_node($one_port, $trigger[$i], 'bool', 'true');
        is(await_value($one_port, $outstanding, "Good $i"), "Good $i", "queue of one: outstanding alarms $i");
    }
    1 while defined next_line($events, 1);
    write_node($one_port, $trigger[0], 'bool', 'false');
    my $promoted = '';
    for (1 .. 8) {
        my $line = next_line($events, $EVENT_SECONDS) // last;
        if ($line =~ /message="((?:Third p|P)rogram alarm with a state)" .* active=1 /) {
            $promoted = $1;
            last;
        }
    }
    is($promoted, 'Program alarm with a state', 'queue of one: the oldest outstanding alarm becomes active');
    is(await_value($one_port, $outstanding, 'Good 1'), 'Good 1', 'queue of one: one alarm is still outstanding');
    write_node($one_port, $trigger[2], 'bool', 'false');
    is(await_value($one_port, $outstanding, 'Good 0'), 'Good 0', 'queue of one: an outstanding alarm that goes out is dropped');
    is(write_node($one_port, $system, 'bool', 'true'), 'Good', 'queue of one: raise the system diagnostics alarm');
    is(await_value($one_port, 'ns=3;s="AlarmTriggers"."Overload_System"', 'Good true'), 'Good true',
        'queue of one: the system diagnostics queue overloads at its limit');
    is(read_node($one_port, 'ns=3;s=SimaticAlarmsAndConditions.SystemDiagnostics.CurrentAlarmsInQueue'), 'Good 1',
        'queue of one: the system diagnostics queue holds one alarm');
    is(write_node($one_port, $system, 'bool', 'false'), 'Good', 'queue of one: clear the system diagnostics alarm');
    is(await_value($one_port, 'ns=3;s="AlarmTriggers"."Overload_System"', 'Good false'), 'Good false',
        'queue of one: the system diagnostics overload ends');
    kill 'INT', $events_pid;
    close($events);
    waitpid($events_pid, 0);
    is(stop_server($one_pid), 0, 'queue of one: the server exits with status 0');
}

# Subscription and monitored item limits: 30 subscriptions over all sessions
# and 10000 items in one subscription.
{
    my (undef, $out) = run_probe($port, [], 'subscriptions', 31);
    is($out, "Good created=30 refused=BadTooManySubscriptions\n", 'subscriptions: the 31st is refused');
    (undef, $out) = run_probe($port, [], 'items', 10001);
    is($out, "Good created=10000 refused=BadTooManyMonitoredItems\n", 'items: the 10001st is refused');
}

# Diagnostic nodes of the server that the function manual names.
{
    my (undef, $summary) = run_probe($port, [], 'browse', 'i=2275');
    my @members = $summary =~ /^\S+ i=\d+$/mg;
    is(scalar @members, 12, 'diagnostics: twelve members of ServerDiagnosticsSummary');
    like($summary, qr/^CurrentSessionCount i=2277$/m, 'diagnostics: CurrentSessionCount');
    like($summary, qr/^SecurityRejectedSessionCount i=2279$/m, 'diagnostics: SecurityRejectedSessionCount');
    my (undef, $sessions) = run_probe($port, [], 'browse', 'i=3706');
    like($sessions, qr/^SessionDiagnosticsArray i=3707$/m, 'diagnostics: SessionDiagnosticsArray');
    (undef, my $array) = run_probe($port, [], 'read', 'i=3707');
    like($array, qr/ActualSessionTimeout: \d/, 'diagnostics: ActualSessionTimeout in the session array');
    my (undef, $server) = run_probe($port, [], 'browse', 'i=2274');
    like($server, qr/^SubscriptionDiagnosticsArray i=2290$/m, 'diagnostics: SubscriptionDiagnosticsArray');
    (undef, my $count) = run_probe($port, [], 'sessions');
    like($count, qr/^Good accepted=(\d+) refused=\S+ current=\1$/, 'diagnostics: CurrentSessionCount equals the open sessions');
}
is(read_node($port, 'i=11702'), 'Good 131072', 'ServerCapabilities: array length');
like(read_node($port, 'ns=3;s="IEC_Timer_0_DB".PT'), qr/^Good 5000$/, 'IEC timer: preset time');

# Values the simulation changes.
my %clock;
$clock{ read_node($port, 'ns=3;s="Clock_Byte"') }++ for 1 .. 12;
cmp_ok(scalar keys %clock, '>=', 3, 'clock memory: the byte changes');
my $before = read_node($port, 'ns=3;s="DataSimulation"."myArray"');
sleep 1.3;
isnt(read_node($port, 'ns=3;s="DataSimulation"."myArray"'), $before, 'simulation: the random array changes');

# An element Variable and its array share one value.
is(write_node($port, 'ns=3;s="DataStatic"."myArrayInt"[3]', 'int16', 99), 'Good', 'array: write an element');
like(read_node($port, 'ns=3;s="DataStatic"."myArrayInt"'), qr/^Good \[1,2,3,99,5,/, 'array: the element is in the array');
is(read_node($port, 'ns=3;s="DataStatic"."myArrayInt"[3]'), 'Good 99', 'array: the element reads back');
is(write_node($port, 'ns=3;s="DataStatic"."myArrayInt"', 'int16[]', join(',', 101 .. 138)), 'Good',
    'array: write the whole array');
is(read_node($port, 'ns=3;s="DataStatic"."myArrayInt"[3]'), 'Good 104',
    'array: an element follows a write of the whole array');

# Access levels.
is(write_node($port, 'ns=3;s="Data_for_OPC_UA_Clients"."NewProduct"', 'bool', 'true'), 'BadNotWritable', 'access: a read-only tag');
is(write_node($port, "$TIMER.ET", 'int32', 5), 'BadNotWritable', 'access: the elapsed time of the IEC timer');

# IEC timer: the output follows the input after the preset time.
is(write_node($port, "$TIMER.PT", 'int32', 1000), 'Good', 'IEC timer: set the preset time');
is(write_node($port, "$TIMER.IN", 'bool', 'true'), 'Good', 'IEC timer: start');
like(read_node($port, "$TIMER.Q"), qr/^Good false$/, 'IEC timer: the output is false at first');
sleep 1.8;
like(read_node($port, "$TIMER.Q"), qr/^Good true$/, 'IEC timer: the output is true after the preset time');
is(write_node($port, "$TIMER.IN", 'bool', 'false'), 'Good', 'IEC timer: stop');

# Methods.
{
    my ($status, @out) = call_method($port, $ADDING, "$ADDING.Method", 'float:1', 'float:5');
    is($status, 'Good', 'method: sum');
    like($out[0] // '', qr/^out 6(\.0+)?$/, 'method: 1 + 5 is 6');
    like(read_node($port, "$ADDING.\"UAMethod_InParameters\".\"number2\""), qr/^Good 5(\.0+)?$/,
        'method: the input of the last call is in the static data');
    like(read_node($port, "$ADDING.\"UAMethod_OutParameters\".\"result\""), qr/^Good 6(\.0+)?$/,
        'method: the output of the last call is in the static data');

    ($status, @out) = call_method($port, $SORT, "$SORT.Method", 'int16[]:9,8,7,6,5,4,3,2,1,0');
    is($status, 'Good', 'method: sort');
    is($out[0] // '', 'out [0,1,2,3,4,5,6,7,8,9]', 'method: sorted ascending');
    ($status) = call_method($port, $SORT, "$SORT.Method", 'int16[]:1,2,3');
    is($status, 'BadInvalidArgument', 'method: an array of the wrong length');

    ($status) = call_method($port, $STATE, "$STATE.Method");
    is($status, 'Good', 'method: first call of the step sequence');
    ($status) = call_method($port, $STATE, "$STATE.Method");
    is($status, 'BadInvalidState', 'method: a call while the sequence runs');
}

# STOP holds the values and rejects methods; RUN restarts from the start values.
is(write_node($port, $RUN_SWITCH, 'bool', 'false'), 'Good', 'STOP: switch');
is(read_node($port, $MODE), 'Good 4', 'STOP: operating state');
{
    my ($status) = call_method($port, $ADDING, "$ADDING.Method", 'float:1', 'float:1');
    is($status, 'BadInvalidState', 'STOP: a method call is rejected');
}
is(write_node($port, 'ns=3;s="DataStatic"."myUdt"."udtInt"', 'int16', 7), 'Good', 'STOP: a write is accepted');
is(write_node($port, $RUN_SWITCH, 'bool', 'true'), 'Good', 'RUN: switch');
is(read_node($port, $MODE), 'Good 8', 'RUN: operating state');
is(read_node($port, 'ns=3;s="DataStatic"."myUdt"."udtInt"'), 'Good 42', 'RUN: a member is back at its start value');
is(read_node($port, 'ns=3;s="DataStatic"."myArrayInt"[3]'), 'Good 4', 'RUN: an array element is back at its start value');
{
    my ($status) = call_method($port, $STATE, "$STATE.Method");
    is($status, 'Good', 'RUN: the method instance is free again');
}

# Alarms: an alarm with a state is reported when it becomes active, when a
# client acknowledges it, and when it becomes inactive.
{
    my ($events_pid, $events) = start_events($port, $NOTIFIER, 12);
    like(next_line($events, $EVENT_SECONDS) // '', qr/^monitor Good$/, 'alarm: subscription accepted');
    is(write_node($port, $TRIGGER, 'bool', 'true'), 'Good', 'alarm: raise');
    my $first = next_line($events, $EVENT_SECONDS) // '';
    like($first, qr/message="Program alarm with a state" severity=720 source=UserProgram active=1 acked=0 retain=1 /,
        'alarm: the first event is active and unacknowledged');
    my ($id)        = $first =~ /eventid=([0-9a-f]+)/;
    my ($condition) = $first =~ /condition=(\S+)/;
    SKIP: {
        skip 'no event id or condition in the first event', 2 if !defined $id || !defined $condition;
        my ($status) = call_method($port, $condition, $ACKNOWLEDGE, "bytestring:$id", 'text:acknowledged by the test');
        is($status, 'Good', 'alarm: acknowledge');
        my $second = next_line($events, $EVENT_SECONDS) // '';
        like($second, qr/active=1 acked=1 /, 'alarm: the acknowledgment is reported');
    }
    is(write_node($port, $TRIGGER, 'bool', 'false'), 'Good', 'alarm: clear');
    my $last = next_line($events, $EVENT_SECONDS) // '';
    like($last, qr/active=0 /, 'alarm: the end of the alarm is reported');
    1 while defined next_line($events, $EVENT_SECONDS);
    close($events);
    waitpid($events_pid, 0);
}

# Event fields that the field lines of the simulation file set: an event
# and an alarm with a state carry them.
{
    my $event_trigger = 'ns=3;s="AlarmTriggers"."Program_Alarm"';
    my ($events_pid, $events) = start_events($port, $NOTIFIER, 12, qw(InfoText AdditionalText_01 ID DisplayClass GroupID));
    like(next_line($events, $EVENT_SECONDS) // '', qr/^monitor Good$/, 'field: subscription accepted');
    is(write_node($port, $event_trigger, 'bool', 'true'), 'Good', 'field: raise the event');
    like(next_line($events, $EVENT_SECONDS) // '',
        qr/ InfoText=Information text of the program alarm AdditionalText_01=First additional text of the program alarm$/,
        'field: an event carries its fields');
    is(write_node($port, $TRIGGER, 'bool', 'true'), 'Good', 'field: raise the alarm with a state');
    like(next_line($events, $EVENT_SECONDS) // '',
        qr/ InfoText=Information text of the alarm with a state AdditionalText_01=First additional text of the alarm with a state ID=2 DisplayClass=1 GroupID=4$/,
        'field: an alarm with a state carries its fields');
    is(write_node($port, $event_trigger, 'bool', 'false'), 'Good', 'field: clear the event trigger');
    is(write_node($port, $TRIGGER, 'bool', 'false'), 'Good', 'field: clear the alarm trigger');
    1 while defined next_line($events, $EVENT_SECONDS);
    close($events);
    waitpid($events_pid, 0);
}

# Associated values that field lines of the simulation file set on an event and
# on an alarm with a state. A field carries the union SimaticAssociatedAlarmValue
# and the probe prints it as "<switch>:<member>:<value>"; the switch is the
# position of the member in the union definition, counted from 1 (Invalid 1,
# Boolean 2, Int16 3, Int32 4, Int64 5, SByte 6, Byte 7, UInt16 8, UInt32 9,
# UInt64 10, Float 11, Double 12, String 13). A value that is not set on an alarm
# with a state prints as the switch 0.
{
    my $event_trigger = 'ns=3;s="AlarmTriggers"."Program_Alarm"';
    my $alarm_trigger = 'ns=3;s="AlarmTriggers"."Program_Alarm_2"';
    my @on_event = (
        'Boolean true', 'Int16 -5', 'Int32 -70000', 'Int64 -9000000000', 'SByte -128',
        'Byte 255', 'UInt16 65535', 'UInt32 4000000000', 'UInt64 18446744073709551615', 'Float 3.14',
    );
    my @on_alarm = ('Double 2.5', 'String hello world', 'Invalid true', 'Boolean false');
    my %position = (Invalid => 1, Boolean => 2, Int16 => 3, Int32 => 4, Int64 => 5, SByte => 6, Byte => 7,
        UInt16 => 8, UInt32 => 9, UInt64 => 10, Float => 11, Double => 12, String => 13);
    my $conf = File::Spec->catfile($dir, 'associated.conf');
    my $lines = '';
    for my $i (0 .. $#on_event) {
        $lines .= sprintf("field %s AssociatedValue_%02d %s\n", $event_trigger, $i + 1, $on_event[$i]);
    }
    for my $i (0 .. $#on_alarm) {
        $lines .= sprintf("field %s AssociatedValue_%02d %s\n", $alarm_trigger, $i + 1, $on_alarm[$i]);
    }
    spew($conf, slurp($SIMULATION) . $lines);
    my @names = map { sprintf('AssociatedValue_%02d', $_) } 1 .. 10;
    my ($associated_pid, $associated_port) = start_server($conf, $config_text);
    my ($events_pid, $events) = start_events($associated_port, $NOTIFIER, 12, @names);
    like(next_line($events, $EVENT_SECONDS) // '', qr/^monitor Good$/, 'associated: subscription accepted');
    is(write_node($associated_port, $event_trigger, 'bool', 'true'), 'Good', 'associated: raise the event');
    my $expected_event = join ' ', map {
        my ($member, $value) = split / /, $on_event[$_], 2;
        sprintf('%s=%d:%s:%s', $names[$_], $position{$member}, $member, $value);
    } 0 .. $#on_event;
    is((next_line($events, $EVENT_SECONDS) // '') =~ / (AssociatedValue_01=.*)$/ ? $1 : '',
        $expected_event, 'associated: an event carries its associated values');
    is(write_node($associated_port, $alarm_trigger, 'bool', 'true'), 'Good', 'associated: raise the alarm with a state');
    my @alarm_words = map {
        my ($member, $value) = split / /, $on_alarm[$_], 2;
        sprintf('%s=%d:%s:%s', $names[$_], $position{$member}, $member, $value);
    } 0 .. $#on_alarm;
    push @alarm_words, map { "$names[$_]=0" } scalar(@on_alarm) .. 9;
    is((next_line($events, $EVENT_SECONDS) // '') =~ / (AssociatedValue_01=.*)$/ ? $1 : '',
        join(' ', @alarm_words), 'associated: an alarm with a state carries its associated values');
    is(write_node($associated_port, $event_trigger, 'bool', 'false'), 'Good', 'associated: clear the event trigger');
    is(write_node($associated_port, $alarm_trigger, 'bool', 'false'), 'Good', 'associated: clear the alarm trigger');
    1 while defined next_line($events, $EVENT_SECONDS);
    close($events);
    waitpid($events_pid, 0);
    is(stop_server($associated_pid), 0, 'associated: the server exits with status 0');
}

# User accounts.
{
    my ($status, $out) = run_probe($port, [qw(-u simulator -p composite)], 'read', $MODE);
    is($out, "Good 8\n", 'user: the account logs in');
    ($status, $out) = run_probe($port, [qw(-u simulator -p wrong)], 'read', $MODE);
    is($status, 1, 'user: a wrong password fails to connect');
    is($out, "connect BadUserAccessDenied\n", 'user: a wrong password is denied');
}

# Secured sessions with every policy and both message security modes.
SKIP: {
    my ($openssl) = grep { -x $_ } map { File::Spec->catfile($_, 'openssl') } File::Spec->path;
    skip 'openssl is not in PATH', 10 if !defined $openssl;
    my $key  = File::Spec->catfile($dir, 'client-key.der');
    my $cert = File::Spec->catfile($dir, 'client-cert.der');
    my $cnf  = File::Spec->catfile($dir, 'client.cnf');
    spew($cnf, <<'CNF');
[req]
distinguished_name = subject
x509_extensions = extensions
prompt = no
[subject]
CN = probe
[extensions]
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment, keyCertSign
extendedKeyUsage = serverAuth, clientAuth
subjectAltName = URI:urn:opcua-server-sim:probe
CNF
    my $made = system { $openssl } $openssl, 'genpkey', '-quiet', '-algorithm', 'RSA',
        '-pkeyopt', 'rsa_keygen_bits:2048', '-outform', 'DER', '-out', $key;
    $made ||= system { $openssl } $openssl, 'req', '-x509', '-new', '-sha256', '-days', '2', '-config', $cnf,
        '-key', $key, '-keyform', 'DER', '-outform', 'DER', '-out', $cert;
    skip 'openssl could not create a client certificate', 10 if $made != 0;
    for my $policy (qw(Basic128Rsa15 Basic256 Basic256Sha256 Aes128_Sha256_RsaOaep Aes256_Sha256_RsaPss)) {
        for my $mode (2, 3) {
            my (undef, $out) = run_probe($port, ['-c', $cert, '-k', $key, '-P', $policy, '-m', $mode], 'read', $MODE);
            is($out, "Good 8\n", "security: $policy, message security mode $mode");
        }
    }
}

is(stop_server($pid), 0, 'stop: the server exits with status 0');

# --- Accounts without anonymous access.
{
    my $conf = File::Spec->catfile($dir, 'noanon.conf');
    spew($conf, "anonymous no\nuser simulator composite\n");
    my ($pid2, $port2) = start_server($conf, $config_text);
    my ($status, $out) = run_probe($port2, [], 'read', 'ns=3;s="DataStatic"."myInt"');
    is($out, "connect BadIdentityTokenRejected\n", 'anonymous no: an anonymous session is refused');
    ($status, $out) = run_probe($port2, [qw(-u simulator -p composite)], 'read', 'ns=3;s="DataStatic"."myInt"');
    is($out, "Good 42\n", 'anonymous no: the account still logs in');
    is(stop_server($pid2), 0, 'anonymous no: the server exits with status 0');
}

# --- The keywords include, limit, and value. The main file includes a file in
# a subdirectory, which includes a file next to itself.
{
    my $sub = File::Spec->catdir($dir, 'sub');
    mkdir $sub or die "$sub: $!\n";
    spew(File::Spec->catfile($sub, 'deeper.conf'),
        "limit max-sessions 5\nlimit publishing-interval-min 200\nlimit sampling-interval-min 50\n"
        . "limit max-browse-continuation-points 5\nlimit max-query-continuation-points 6\n"
        . "limit max-history-continuation-points 7\n");
    spew(File::Spec->catfile($sub, 'part.conf'), "include deeper.conf\nvalue ns=3;s=\"DataStatic\".\"myInt\" 7\n");
    my $main = File::Spec->catfile($dir, 'keywords.conf');
    spew($main, "include sub/part.conf\noperating-mode $MODE run=8 stop=4\n");
    my ($pid3, $port3) = start_server($main, $config_text);
    is(read_node($port3, 'ns=3;s="DataStatic"."myInt"'), 'Good 7', 'value: sets a Variable from an included file');
    my (undef, $out) = run_probe($port3, [], 'sessions');
    is($out, "Good accepted=5 refused=BadTooManySessions current=5\n", 'limit: the session count');
    (undef, $out) = run_probe($port3, [], 'intervals', 'ns=3;s="DataStatic"."myInt"');
    is($out, "Good publishing=200 sampling=50\n", 'limit: the minimum intervals');
    is(read_node($port3, 'i=2735'), 'Good 5', 'limit: the browse continuation point count');
    is(read_node($port3, 'i=2736'), 'Good 6', 'limit: the query continuation point count');
    is(read_node($port3, 'i=2737'), 'Good 7', 'limit: the history continuation point count');
    is(write_node($port3, 'ns=3;s="DataStatic"."myInt"', 'int16', 99), 'Good', 'value: write another value');
    is(write_node($port3, $RUN_SWITCH, 'bool', 'false'), 'Good', 'value: STOP');
    is(write_node($port3, $RUN_SWITCH, 'bool', 'true'), 'Good', 'value: RUN');
    is(read_node($port3, 'ns=3;s="DataStatic"."myInt"'), 'Good 7', 'value: the number is the start value after a restart');
    is(stop_server($pid3), 0, 'keywords: the server exits with status 0');
}

# --- The limits of each CPU class. The 1515 and 1516 class is the shipped
# simulation file; the other two classes are profile files that include it.
for my $class (
    { name => '1511 to 1513', file => 'simulation-1511-1513.conf', sessions => 32, publishing => 200,
      sampling => 100, program => 100, diagnostics => 50 },
    { name => '1515 and 1516', file => 'simulation.conf', sessions => 48, publishing => 100,
      sampling => 100, program => 200, diagnostics => 100 },
    { name => '1517 and 1518', file => 'simulation-1517-1518.conf', sessions => 64, publishing => 10,
      sampling => 10, program => 400, diagnostics => 200 },
) {
    my ($class_pid, $class_port) = start_server(File::Spec->catfile($MODEL, $class->{file}), $config_text);
    is(read_node($class_port, $RUN_SWITCH), 'Good true', "class $class->{name}: the shipped simulation is included");
    my (undef, $out) = run_probe($class_port, [], 'sessions');
    is($out, "Good accepted=$class->{sessions} refused=BadTooManySessions current=$class->{sessions}\n",
        "class $class->{name}: sessions");
    (undef, $out) = run_probe($class_port, [], 'intervals', 'ns=3;s="DataStatic"."myInt"');
    is($out, "Good publishing=$class->{publishing} sampling=$class->{sampling}\n", "class $class->{name}: intervals");
    is(read_node($class_port, 'ns=3;s=SimaticAlarmsAndConditions.ProgramAlarms.MaxAlarmsInQueue'),
        "Good $class->{program}", "class $class->{name}: program alarm queue");
    is(read_node($class_port, 'ns=3;s=SimaticAlarmsAndConditions.SystemDiagnostics.MaxAlarmsInQueue'),
        "Good $class->{diagnostics}", "class $class->{name}: system diagnostics alarm queue");
    is(stop_server($class_pid), 0, "class $class->{name}: the server exits with status 0");
}

# --- Inputs the server rejects. Each case names the line of the file.
my $PA = 'ns=3;s="AlarmTriggers"."Program_Alarm"';
my $EV = "event ns=3;i=1804 $NOTIFIER $PA 300 myText\n";
my @cases = (
    { name => 'unknown keyword', text => "cycle 100\n# comment\nbogus line\n", line => 3 },
    { name => 'unknown node of a signal', text => "cycle 100\nsignal ns=3;s=\"Nope\".\"x\" ramp\n", line => 2 },
    { name => 'unknown kind of a signal', text => "signal ns=3;s=\"DataStatic\".\"myInt\" wave\n", line => 1 },
    { name => 'second operating mode', text => "operating-mode $MODE run=8 stop=4\noperating-mode $MODE run=8 stop=4\n", line => 2 },
    { name => 'unknown event type', text => "event ns=3;i=99999 $NOTIFIER $TRIGGER 300 text\n", line => 1 },
    { name => 'unknown event source', text => "event ns=3;i=1804 ns=3;s=Nowhere $TRIGGER 300 text\n", line => 1 },
    { name => 'severity above 1000', text => "alarm ns=3;i=1805 $NOTIFIER $TRIGGER 1001 text\n", line => 1 },
    { name => 'unknown structure of a method', text => "method $ADDING.Method sum in=ns=3;s=\"Nope\"\n", line => 1 },
    { name => 'cycle of zero', text => "cycle 0\n", line => 1 },
    { name => 'comment of 5000 characters before a bad line', text => "# " . ('x' x 5000) . "\nbogus\n", line => 2 },
    { name => 'include of a missing file', text => "# comment\ninclude missing.conf\n", line => 2 },
    { name => 'include of the file itself', text => "include case.conf\n", line => 1 },
    { name => 'include of a directory', text => "include sub\n", line => 1 },
    { name => 'include with an extra word', text => "include sub/deeper.conf extra\n", line => 1 },
    { name => 'limit with an unknown name', text => "limit nope 5\n", line => 1 },
    { name => 'limit with a text instead of a number', text => "limit max-sessions abc\n", line => 1 },
    { name => 'limit with an interval below the smallest', text => "limit publishing-interval-min 1\n", line => 1 },
    { name => 'limit with a fraction as session count', text => "limit max-sessions 2.5\n", line => 1 },
    { name => 'value with a text instead of a number', text => "value ns=3;s=\"DataStatic\".\"myInt\" abc\n", line => 1 },
    { name => 'value of an unknown node', text => "value ns=3;s=\"Nope\" 1\n", line => 1 },
    { name => 'value of a node that is no Variable', text => "value ns=3;s=PLC 1\n", line => 1 },
    { name => 'field of a trigger without an alarm line', text => "field $PA InfoText text\n", line => 1 },
    { name => 'field with an unknown name', text => "${EV}field $PA Nope 5\n", line => 2 },
    { name => 'field without a value', text => "${EV}field $PA InfoText\n", line => 2 },
    { name => 'field with a text instead of a number', text => "${EV}field $PA ID abc\n", line => 2 },
    { name => 'field with an ID above 65535', text => "${EV}field $PA ID 70000\n", line => 2 },
    { name => 'field with a group above 255', text => "${EV}field $PA GroupID 300\n", line => 2 },
    { name => 'field set twice', text => "${EV}field $PA InfoText one\nfield $PA InfoText two\n", line => 3 },
    { name => 'associated value with an unknown member', text => "${EV}field $PA AssociatedValue_01 Nope 5\n", line => 2 },
    { name => 'associated value with a number of 11', text => "${EV}field $PA AssociatedValue_11 Int16 5\n", line => 2 },
    { name => 'associated value with a number of 00', text => "${EV}field $PA AssociatedValue_00 Int16 5\n", line => 2 },
    { name => 'associated value without a value', text => "${EV}field $PA AssociatedValue_01 Int16\n", line => 2 },
    { name => 'associated value with a text instead of a number', text => "${EV}field $PA AssociatedValue_01 Int16 abc\n", line => 2 },
    { name => 'associated value of a Byte above 255', text => "${EV}field $PA AssociatedValue_01 Byte 256\n", line => 2 },
    { name => 'associated value of a UInt16 below zero', text => "${EV}field $PA AssociatedValue_01 UInt16 -1\n", line => 2 },
    { name => 'associated value of a Boolean with a number', text => "${EV}field $PA AssociatedValue_01 Boolean 2\n", line => 2 },
    { name => 'associated value of an SByte above 127', text => "${EV}field $PA AssociatedValue_01 SByte 128\n", line => 2 },
    { name => 'associated value of an Int16 above 32767', text => "${EV}field $PA AssociatedValue_01 Int16 32768\n", line => 2 },
    { name => 'associated value of an Int32 above 2147483647', text => "${EV}field $PA AssociatedValue_01 Int32 2147483648\n", line => 2 },
    { name => 'associated value of an Int64 above 9223372036854775807', text => "${EV}field $PA AssociatedValue_01 Int64 9223372036854775808\n", line => 2 },
    { name => 'associated value of a UInt16 above 65535', text => "${EV}field $PA AssociatedValue_01 UInt16 65536\n", line => 2 },
    { name => 'associated value of a UInt32 above 4294967295', text => "${EV}field $PA AssociatedValue_01 UInt32 4294967296\n", line => 2 },
    { name => 'associated value of a UInt64 above 18446744073709551615', text => "${EV}field $PA AssociatedValue_01 UInt64 18446744073709551616\n", line => 2 },
    { name => 'associated value of a Float above the largest float', text => "${EV}field $PA AssociatedValue_01 Float 1e39\n", line => 2 },
    { name => 'associated value of a Double that is not finite', text => "${EV}field $PA AssociatedValue_01 Double inf\n", line => 2 },
);
for my $case (@cases) {
    my $conf = File::Spec->catfile($dir, 'case.conf');
    spew($conf, $case->{text});
    my ($status, $text) = run_failing_server($conf);
    is($status, 1, "$case->{name}: exit status");
    like($text, qr/line $case->{line} cannot be applied/, "$case->{name}: names line $case->{line}");
}
# An error inside an included file names the file and its line, and the line
# of the include in the including file.
{
    my $sub = File::Spec->catdir($dir, 'broken');
    mkdir $sub or die "$sub: $!\n";
    spew(File::Spec->catfile($sub, 'bad.conf'), "# fine\nbogus\n");
    my $conf = File::Spec->catfile($dir, 'case.conf');
    spew($conf, "# one\n# two\ninclude broken/bad.conf\n");
    my ($status, $text) = run_failing_server($conf);
    is($status, 1, 'include of a broken file: exit status');
    like($text, qr{bad\.conf line 2 cannot be applied}, 'include of a broken file: names the line in the file');
    like($text, qr{case\.conf line 3 cannot be applied}, 'include of a broken file: names the line of the include');
}

# Started without a configuration file, the server prints its usage and exits
# with status 2.
{
    my $log = File::Spec->catfile($dir, 'usage.log');
    my $usage_pid = fork();
    defined $usage_pid or die "fork: $!\n";
    if (!$usage_pid) {
        open(STDOUT, '>', $log) or POSIX::_exit(126);
        open(STDERR, '>&', \*STDOUT) or POSIX::_exit(126);
        alarm $START_SECONDS;
        { exec { $SERVER } $SERVER; }
        POSIX::_exit(127);
    }
    waitpid($usage_pid, 0);
    my $status = ($? & 127) ? 'signal ' . ($? & 127) : $? >> 8;
    is($status, 2, 'usage: exit status');
    like(slurp($log), qr/^usage: /, 'usage: the message names the arguments');
}
{
    my ($status, $text) = run_failing_server('/nonexistent.conf');
    is($status, 1, 'missing simulation file: exit status');
    like($text, qr/cannot open \/nonexistent\.conf/, 'missing simulation file: message');
    ($status, $text) = run_failing_server($dir);
    is($status, 1, 'simulation file that is a directory: exit status');
    like($text, qr/cannot read /, 'simulation file that is a directory: message');
}

done_testing();
