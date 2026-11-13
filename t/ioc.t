#!/usr/bin/env perl
#
# Integration test of the composite model with an EPICS IOC that uses the opcua
# device support module. The test starts the built server with the shipped
# configuration, simulation file, and NodeSets, starts ioc/st.cmd through
# iocsh.bash of an EPICS distribution tree, and reads and writes the model
# through the IOC with caget and caput. The server side is read and written with
# the built opcua-probe client. Only ports are replaced (the server port in a
# copy of the server configuration, the Channel Access and PVAccess ports of the
# IOC in its environment).
#
# "make test" builds the binaries and names them in SIM_SERVER, SIM_PROBE, and
# SIM_DI, and names the distribution tree in SIM_EPICS_TREE (the make variable
# EPICS_TREE). The test is skipped when the tree is not named or has no
# iocsh.bash.
#
# Check design. Every check sets the state it reads. The expected values come
# from the model (plc.json start values, simulation.conf) and are never read
# back from the server under test. A wait ends on the first observation of the
# expected value or after WAIT_SECONDS, and the check then judges the last
# observed value.
#
#   check  claim                                         input and expected value
#   T1     the IOC reports the start values              no input; Bool true, Byte 171, Word 52719, Int 42
#   T2     IOC write reaches the member node             caput 77 to udtInt; probe reads 77
#   T2     a member write leaves the others unchanged    YEAR before and after the write of udtInt
#   T2     server write reaches the IOC                  probe writes 31 to udtInt; the IOC record reads 31
#   T2     a write of YEAR through the structure         caput 2000 to YEAR; probe reads 2000
#   T3     IOC write to the element reaches the array    caput 99 to element 3; probe and waveform read 99
#   T3     server write to the element reaches the IOC   probe writes 55; record and waveform read 55
#   T4     values arrive by subscription                 records are on I/O Intr; at least 3 distinct
#                                                        values of Clock_Byte and of DataSimulation myInt
#   T5     STOP and RUN                                  caput 0 changes the mode to 4, caput 1 changes it to 8 and
#                                                        udtInt (77 before) is back at 42
#   T6     secured session                               the IOC log names the user simulator, mode
#                                                        SignAndEncrypt, policy Basic256Sha256; the value
#                                                        of Byte read over it is 171

use strict;
use warnings;

use Cwd qw(abs_path);
use File::Basename qw(dirname);
use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use IO::Socket::INET;
use POSIX ();
use Sys::Hostname qw(hostname);
use Test::More;
use Time::HiRes qw(sleep time);

my ($SERVER, $PROBE, $DI, $TREE) = @ENV{qw(SIM_SERVER SIM_PROBE SIM_DI SIM_EPICS_TREE)};
plan skip_all => 'run "make test": SIM_SERVER, SIM_PROBE, and SIM_DI name the built binaries and the DI NodeSet'
    if !defined $SERVER || !defined $PROBE || !defined $DI || !-x $SERVER || !-x $PROBE || !-f $DI;
plan skip_all => 'run "make test EPICS_TREE=<distribution tree>": the EPICS distribution tree is not named'
    if !defined $TREE || $TREE eq '';

my ($IOCSH) = glob(File::Spec->catfile($TREE, 'base', 'bin', '*', 'iocsh.bash'));
plan skip_all => "iocsh.bash is not found in $TREE/base/bin/*/"
    if !defined $IOCSH || !-x $IOCSH;
my $BIN    = dirname($IOCSH);
my $CAGET  = File::Spec->catfile($BIN, 'caget');
my $CAPUT  = File::Spec->catfile($BIN, 'caput');
plan skip_all => "caget and caput are not found in $BIN"
    if !-x $CAGET || !-x $CAPUT;
plan skip_all => 'openssl is needed for the client certificate'
    if !grep { -x File::Spec->catfile($_, 'openssl') } File::Spec->path;

my $TOP   = abs_path(File::Spec->catdir(dirname(__FILE__), File::Spec->updir));
my $MODEL = File::Spec->catdir($TOP, 'models', 's7-1500-composite');
my $NODESET    = File::Spec->catfile($MODEL, 's7-1500-composite.NodeSet2.xml');
my $SIMULATION = File::Spec->catfile($MODEL, 'simulation.conf');
my $SERVER_CERT = File::Spec->catfile($MODEL, 'pki', 'server-cert.der');
plan skip_all => 'run "make certificate": the server certificate of the model is missing'
    if !-f $SERVER_CERT;

# Limits of the test in seconds: the server and the IOC start, one wait for a
# value, one command, the IOC end after "exit", and the observation of values.
my $START_SECONDS   = 30;
my $WAIT_SECONDS    = 10;
my $COMMAND_SECONDS = 20;
my $EXIT_SECONDS    = 20;
my $WATCH_SECONDS   = 6;

# Node ids on the server side.
my $UDT_INT = 'ns=3;s="DataStatic"."myUdt"."udtInt"';
my $UDT_YEAR = 'ns=3;s="DataStatic"."myUdt"."udtTime"."YEAR"';
my $ELEMENT = 'ns=3;s="DataStatic"."myArrayInt"[3]';
my $MODE    = 'ns=3;s=OperatingMode';
my $SECURE_NODE = 'ns=3;s="DataStatic"."myByte"';

my $dir = tempdir(CLEANUP => 1);
my ($server_pid, $ioc_pid, $ioc_hold);
END {
    if (defined $ioc_pid) {
        kill 'TERM', $ioc_pid;
        waitpid($ioc_pid, 0);
    }
    if (defined $server_pid) {
        kill 'INT', $server_pid;
        waitpid($server_pid, 0);
    }
}

# Returns distinct free TCP ports from one set of open sockets, so that no two
# of them are equal.
sub free_ports {
    my ($count) = @_;
    my @sockets = map {
        IO::Socket::INET->new(Listen => 1, LocalAddr => '127.0.0.1', LocalPort => 0, Proto => 'tcp')
            or die "free port: $!\n"
    } 1 .. $count;
    my @ports = map { $_->sockport } @sockets;
    close($_) for @sockets;
    return @ports;
}

sub slurp {
    my ($path) = @_;
    open(my $fh, '<:raw', $path) or return '';
    local $/;
    my $data = <$fh>;
    close($fh);
    return defined $data ? $data : '';
}

sub spew {
    my ($path, $data) = @_;
    open(my $fh, '>:raw', $path) or die "$path: $!\n";
    print {$fh} $data or die "$path: $!\n";
    close($fh) or die "$path: $!\n";
    return;
}

# Runs a command with a time limit and returns its standard output without the
# trailing newline.
sub run_cmd {
    my (@argv) = @_;
    my $pid = open(my $out, '-|');
    defined $pid or die "fork: $!\n";
    if (!$pid) {
        open(STDERR, '>', File::Spec->devnull) or POSIX::_exit(126);
        alarm $COMMAND_SECONDS;
        { exec { $argv[0] } @argv; }
        POSIX::_exit(127);
    }
    my $stdout = do { local $/; <$out> };
    close($out);
    $stdout = '' if !defined $stdout;
    $stdout =~ s/\s+\z//;
    return $stdout;
}

# Server side, through the probe client. The result of a read is "Good 42".
sub probe {
    my ($port, @args) = @_;
    return run_cmd($PROBE, "opc.tcp://localhost:$port", @args);
}

# IOC side. caget returns the value text; caput writes to a record that is
# processed by the put.
sub caget {
    my (@pvs) = @_;
    return run_cmd($CAGET, '-t', '-w', '3', @pvs);
}

sub caput {
    my ($pv, $value) = @_;
    return run_cmd($CAPUT, '-t', '-w', '3', $pv, $value);
}

# Writes a record on I/O Intr: a put does not process such a record, so the
# record is processed by the next put to its PROC field.
sub caput_process {
    my ($pv, $value) = @_;
    caput($pv, $value);
    return caput("$pv.PROC", 1);
}

# Calls a function until its result is true or the time is up; returns the
# last result.
sub wait_for {
    my ($seconds, $test) = @_;
    my $deadline = time + $seconds;
    my $result;
    while (1) {
        $result = $test->();
        return $result if $result || time >= $deadline;
        sleep 0.25;
    }
}

# Waits until a function returns the expected text and returns the last text.
sub wait_value {
    my ($expected, $reader) = @_;
    my $value = '';
    wait_for($WAIT_SECONDS, sub { $value = $reader->(); return $value eq $expected; });
    return $value;
}

# Waits until a reader returns a value other than the one given, so that the
# value of the step before cannot pass for the result of this step, and returns
# the last value.
sub wait_change {
    my ($before, $reader) = @_;
    my $value = $before;
    wait_for($WAIT_SECONDS, sub { $value = $reader->(); return $value ne $before; });
    return $value;
}

# The fifth value in "5 1 2 3 4 5" is element 3: the first number is the count.
sub waveform_element {
    my ($index) = @_;
    my @fields = split ' ', caget('-#', 5, 'SIM:Array:Int');
    return defined $fields[$index + 1] ? $fields[$index + 1] : '';
}

sub probe_value {
    my ($port, $node) = @_;
    return probe($port, 'read', $node);
}

# ---- environment of the server and the IOC -------------------------------

my ($opc_port, $ca_port, $repeater_port, $pva_port, $pva_broadcast_port) = free_ports(5);

# The client certificate carries the application URI of the opcua module, which
# is urn:ioc@<host name>:EPICS:IOC, and the PKI store trusts the server
# certificate of the model.
my $secure = File::Spec->catdir($dir, 'secure');
make_path(File::Spec->catdir($secure, 'pki', 'trusted', 'certs'), File::Spec->catdir($secure, 'pki', 'issuers', 'certs'));
copy($SERVER_CERT, File::Spec->catfile($secure, 'pki', 'trusted', 'certs', 'server-cert.der')) or die "copy: $!\n";
my $host = hostname();
spew(File::Spec->catfile($secure, 'client.cnf'), <<"CNF");
[req]
distinguished_name = subject
x509_extensions = extensions
prompt = no
[subject]
CN = opcua-ioc-test
[extensions]
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment, keyCertSign
extendedKeyUsage = critical, serverAuth, clientAuth
subjectAltName = URI:urn:ioc\@$host:EPICS:IOC, DNS:$host
CNF
run_cmd('openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', 2,
    '-config', File::Spec->catfile($secure, 'client.cnf'),
    '-keyout', File::Spec->catfile($secure, 'key.pem'), '-out', File::Spec->catfile($secure, 'cert.pem'));
die "openssl could not create the client certificate\n"
    if !-s File::Spec->catfile($secure, 'cert.pem') || !-s File::Spec->catfile($secure, 'key.pem');

# The account is the one of the simulation file.
my ($user, $password) = slurp($SIMULATION) =~ /^user\s+(\S+)\s+(\S+)/m or die "no user line in $SIMULATION\n";
spew(File::Spec->catfile($secure, 'ident.txt'), "user=$user\npass=$password\n");

@ENV{qw(SIM_IOC_DIR SIM_OPC_PORT SIM_SECURE_DIR)} = (File::Spec->catdir($TOP, 'ioc'), $opc_port, $secure);
%ENV = (%ENV,
    EPICS_CA_SERVER_PORT       => $ca_port,
    EPICS_CA_REPEATER_PORT     => $repeater_port,
    EPICS_CA_ADDR_LIST         => '127.0.0.1',
    EPICS_CA_AUTO_ADDR_LIST    => 'NO',
    EPICS_CAS_INTF_ADDR_LIST   => '127.0.0.1',
    EPICS_PVA_SERVER_PORT      => $pva_port,
    EPICS_PVA_BROADCAST_PORT   => $pva_broadcast_port,
    EPICS_PVAS_SERVER_PORT     => $pva_port,
    EPICS_PVAS_BROADCAST_PORT  => $pva_broadcast_port,
    EPICS_PVAS_INTF_ADDR_LIST  => '127.0.0.1',
    EPICS_PVA_ADDR_LIST        => '127.0.0.1',
    EPICS_PVA_AUTO_ADDR_LIST   => 'NO',
);

# ---- server --------------------------------------------------------------

my $server_log = File::Spec->catfile($dir, 'server.log');
{
    my $config = File::Spec->catfile($dir, 'server.json5');
    (my $text = slurp(File::Spec->catfile($MODEL, 'server.json5'))) =~ s{opc\.tcp://:4840}{opc.tcp://:$opc_port};
    spew($config, $text);
    $server_pid = fork();
    defined $server_pid or die "fork: $!\n";
    if (!$server_pid) {
        chdir $MODEL or POSIX::_exit(126);
        open(STDOUT, '>', $server_log) or POSIX::_exit(126);
        open(STDERR, '>&', \*STDOUT) or POSIX::_exit(126);
        { exec { $SERVER } $SERVER, '-s', $SIMULATION, $config, $DI, $NODESET; }
        POSIX::_exit(127);
    }
}
my $server_up = wait_for($START_SECONDS, sub { probe($opc_port, 'read', $MODE) =~ /^Good / });

# ---- IOC -----------------------------------------------------------------
#
# iocsh.bash ends only on a signal or on "exit" while its standard input stays
# open, so the standard input is a fifo whose write side the test holds. The IOC
# runs in a directory of the test, away from the repository and the tree.

my $ioc_log = File::Spec->catfile($dir, 'ioc.log');
my $fifo    = File::Spec->catfile($dir, 'ioc.in');
POSIX::mkfifo($fifo, 0600) or die "mkfifo: $!\n";
open($ioc_hold, '+<', $fifo) or die "$fifo: $!\n";
{
    my $run = File::Spec->catdir($dir, 'run');
    make_path($run);
    $ioc_pid = fork();
    defined $ioc_pid or die "fork: $!\n";
    if (!$ioc_pid) {
        chdir $run or POSIX::_exit(126);
        open(STDIN, '<', $fifo) or POSIX::_exit(126);
        open(STDOUT, '>', $ioc_log) or POSIX::_exit(126);
        open(STDERR, '>&', \*STDOUT) or POSIX::_exit(126);
        { exec { $IOCSH } $IOCSH, '-e', $TREE, File::Spec->catfile($TOP, 'ioc', 'st.cmd'); }
        POSIX::_exit(127);
    }
}
my $ioc_up = wait_for($START_SECONDS, sub {
    my $log = slurp($ioc_log);
    return $log =~ /iocRun: All initialization complete/ && $log =~ /\d+\.\d+\.\d+ > /;
});
# The first session is connected when the operating mode record has a value.
my $ioc_connected = wait_for($START_SECONDS, sub { caget('SIM:Mode') ne '' });

ok($server_up, 'the server answers the probe');
ok($ioc_up, 'the IOC reaches its prompt');
is($ioc_connected ? caget('SIM:Mode') : '', 8, 'the IOC record of the operating mode has the value of RUN');

# ---- T1: start values ----------------------------------------------------

is(caget('SIM:Static:Bool'), 'true', 'T1 myBool start value');
is(caget('SIM:Static:Byte'), 171, 'T1 myByte start value');
is(caget('SIM:Static:Word'), 52719, 'T1 myWord start value');
is(caget('SIM:Static:Int'), 42, 'T1 myInt start value');

# ---- T2: structure members -----------------------------------------------

{
    my $year_before = caget('SIM:Udt:Year');
    caput_process('SIM:Udt:Int', 77);
    my $server_value = '';
    wait_for($WAIT_SECONDS, sub { $server_value = probe_value($opc_port, $UDT_INT); $server_value eq 'Good 77' });
    is($server_value, 'Good 77', 'T2 IOC write of udtInt reaches the member node');
    is(caget('SIM:Udt:Year'), $year_before, 'T2 the write of udtInt leaves YEAR unchanged in the IOC');
    is(probe_value($opc_port, $UDT_YEAR), "Good $year_before", 'T2 the write of udtInt leaves the YEAR node unchanged');
}
{
    probe($opc_port, 'write', $UDT_INT, 'int16', 31);
    is(wait_value(31, sub { caget('SIM:Udt:Int') }), 31, 'T2 server write of udtInt reaches the IOC');
}
{
    caput_process('SIM:Udt:Year', 2000);
    my $server_value = '';
    wait_for($WAIT_SECONDS, sub { $server_value = probe_value($opc_port, $UDT_YEAR); $server_value eq 'Good 2000' });
    is($server_value, 'Good 2000', 'T2 IOC write of YEAR reaches the nested member node');
}

# ---- T3: array and element -----------------------------------------------

{
    caput_process('SIM:Array:Elem3', 99);
    my $server_value = '';
    wait_for($WAIT_SECONDS, sub { $server_value = probe_value($opc_port, $ELEMENT); $server_value eq 'Good 99' });
    is($server_value, 'Good 99', 'T3 IOC write reaches the element node');
    is(wait_value(99, sub { waveform_element(3) }), 99, 'T3 IOC write to the element shows in the array');
}
{
    probe($opc_port, 'write', $ELEMENT, 'int16', 55);
    is(wait_value(55, sub { caget('SIM:Array:Elem3') }), 55, 'T3 server write reaches the element record');
    is(wait_value(55, sub { waveform_element(3) }), 55, 'T3 server write to the element shows in the array');
}

# ---- T4: values by subscription ------------------------------------------

{
    is(caget('SIM:Clock:Byte.SCAN'), 'I/O Intr', 'T4 the clock record is on I/O Intr');
    is(caget('SIM:Sim:Int.SCAN'), 'I/O Intr', 'T4 the simulation record is on I/O Intr');
    my (%clock, %simulated);
    my $deadline = time + $WATCH_SECONDS;
    while (time < $deadline) {
        $clock{caget('SIM:Clock:Byte')} = 1;
        $simulated{caget('SIM:Sim:Int')} = 1;
        sleep 0.2;
    }
    cmp_ok(scalar(keys %clock), '>=', 3, 'T4 Clock_Byte changes');
    cmp_ok(scalar(keys %simulated), '>=', 3, 'T4 DataSimulation myInt changes');
}

# ---- T5: STOP and RUN ----------------------------------------------------

{
    caput_process('SIM:Udt:Int', 77);
    wait_for($WAIT_SECONDS, sub { probe_value($opc_port, $UDT_INT) eq 'Good 77' });
    my $running = caget('SIM:Mode');
    caput('SIM:Run', 0);
    is(wait_change($running, sub { caget('SIM:Mode') }), 4, 'T5 STOP shows operating mode 4');
    my $stopped = caget('SIM:Mode');
    caput('SIM:Run', 1);
    is(wait_change($stopped, sub { caget('SIM:Mode') }), 8, 'T5 RUN shows operating mode 8');
    is(wait_value(42, sub { caget('SIM:Udt:Int') }), 42, 'T5 RUN returns udtInt to its start value in the IOC');
    is(probe_value($opc_port, $UDT_INT), 'Good 42', 'T5 RUN returns udtInt to its start value on the server');
}

# ---- T6: secured session -------------------------------------------------

{
    my $log = '';
    wait_for($WAIT_SECONDS, sub {
        $log = slurp($ioc_log);
        return $log =~ /OPC UA session OPC2: connected as '\Q$user\E' \(username token\) with security level \d+ \(mode=SignAndEncrypt; policy=Basic256Sha256\)/;
    });
    like($log, qr/OPC UA session OPC2: connected as '\Q$user\E' \(username token\) with security level \d+ \(mode=SignAndEncrypt; policy=Basic256Sha256\)/,
        'T6 the secured session opens as the user of the simulation file');
    my $server_value = probe_value($opc_port, $SECURE_NODE);
    is(wait_value(171, sub { caget('SIM:Secure:Byte') }), 171, 'T6 the value of myByte read over the secured session');
    is($server_value, 'Good 171', 'T6 the server holds the same value of myByte');
}

# ---- IOC end -------------------------------------------------------------

{
    print {$ioc_hold} "exit\n";
    $ioc_hold->flush;
    my $status;
    wait_for($EXIT_SECONDS, sub {
        my $done = waitpid($ioc_pid, POSIX::WNOHANG());
        $status = $? if $done != 0;
        return $done != 0;
    });
    my $ended = defined $status;
    $ioc_pid = undef if $ended;
    ok($ended, 'the IOC ends after "exit"');
}

diag('IOC log:' . "\n" . slurp($ioc_log)) if !Test::More->builder->is_passing;

done_testing();
