#!/usr/bin/env perl
#
# Cases of scripts/run-model.bash. Each case runs the script as a subprocess
# on a model directory that the test assembles in a temporary directory: the
# NodeSet of the generic description in t/fixtures/interface.json, written by
# tools/server-interface-nodeset.pl, and a copy of the composite model. The
# script starts the built server, which the test checks with the built
# opcua-probe client. Only the port is replaced, in a copy of the server
# configuration. "make test" builds the binaries and names them in SIM_SERVER,
# SIM_PROBE, and SIM_DI.

use strict;
use warnings;

use Cwd qw(abs_path);
use File::Basename qw(dirname);
use File::Copy qw(copy);
use File::Spec;
use File::Temp qw(tempdir);
use IO::Socket::INET;
use POSIX ();
use Test::More;
use Time::HiRes qw(sleep time);

my ($SERVER, $PROBE, $DI) = @ENV{qw(SIM_SERVER SIM_PROBE SIM_DI)};
plan skip_all => 'run "make test": SIM_SERVER, SIM_PROBE, and SIM_DI name the built binaries and the DI NodeSet'
    if !defined $SERVER || !defined $PROBE || !defined $DI || !-x $SERVER || !-x $PROBE || !-f $DI;

my $TOP     = abs_path(File::Spec->catdir(dirname(__FILE__), File::Spec->updir));
my $SCRIPT  = File::Spec->catfile($TOP, 'scripts', 'run-model.bash');
my $TOOL    = File::Spec->catfile($TOP, 'tools', 'server-interface-nodeset.pl');
my $FIXTURES = File::Spec->catdir($TOP, 't', 'fixtures');
my $MODEL   = File::Spec->catdir($TOP, 'models', 's7-1500-composite');
plan skip_all => 'run "make build": the script starts build/opcua-server-sim of the tree'
    if !-x File::Spec->catfile($TOP, 'build', 'opcua-server-sim');
plan skip_all => 'run "make certificate": the server certificate of the model is missing'
    if !-f File::Spec->catfile($MODEL, 'pki', 'server-cert.der');

# Seconds to wait for the server to answer, for a script that must end by
# itself, and for one probe command.
my $START_SECONDS   = 20;
my $SCRIPT_SECONDS  = 20;
my $COMMAND_SECONDS = 30;

# Variables the probe reads: one of the fixture, and of the composite model one
# of the model and the simulator control node that exists only when the
# simulation file of the directory is used.
my $FIXTURE_NODE   = 'ns=2;s=demoInterface.sensors.unitA.flag';
my $COMPOSITE_NODE = 'ns=3;s=OperatingMode';
my $SIMULATOR_NODE = 'ns=4;s=Simulator.Run';

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

# Runs a command to its end and returns the exit status, the standard output,
# and the standard error.
sub run_command {
    my (@command) = @_;
    my $err = File::Temp->new;
    my $pid = open(my $out, '-|');
    defined $pid or die "fork: $!\n";
    if (!$pid) {
        open(STDERR, '>&', $err) or POSIX::_exit(126);
        $ENV{LC_ALL} = 'C';
        alarm $SCRIPT_SECONDS;
        { exec { $command[0] } @command; }
        POSIX::_exit(127);
    }
    my $stdout = do { local $/; <$out> };
    close($out);
    my $status = ($? & 127) ? 'signal ' . ($? & 127) : $? >> 8;
    seek($err, 0, 0);
    my $stderr = do { local $/; <$err> };
    return ($status, defined $stdout ? $stdout : '', defined $stderr ? $stderr : '');
}

sub probe {
    my ($port, @args) = @_;
    my $pid = open(my $out, '-|');
    defined $pid or die "fork: $!\n";
    if (!$pid) {
        open(STDERR, '>', File::Spec->devnull) or POSIX::_exit(126);
        alarm $COMMAND_SECONDS;
        { exec { $PROBE } $PROBE, "opc.tcp://localhost:$port", @args; }
        POSIX::_exit(127);
    }
    my $text = do { local $/; <$out> };
    close($out);
    $text = '' if !defined $text;
    chomp $text;
    return $text;
}

# Returns the text of a server configuration with the port replaced.
sub config_with_port {
    my ($path, $port) = @_;
    (my $text = slurp($path)) =~ s{opc\.tcp://:4840}{opc.tcp://:$port};
    return $text;
}

# Makes a model directory below the temporary directory, with the server
# configuration of the fixtures on a free port, and returns its path and port.
my $count = 0;
sub new_model {
    my $path = File::Spec->catdir($dir, 'model' . ++$count);
    mkdir $path or die "$path: $!\n";
    my $port = free_port();
    spew(File::Spec->catfile($path, 'server.json5'),
        config_with_port(File::Spec->catfile($FIXTURES, 'server.json5'), $port));
    return ($path, $port);
}

# Writes the NodeSet of the fixture description into a file with the tool.
sub write_nodeset {
    my ($path) = @_;
    my ($status) = run_command($^X, $TOOL, '--output', $path,
        File::Spec->catfile($FIXTURES, 'interface.json'));
    die "the tool failed with status $status\n" if $status ne '0';
    return;
}

# Starts the script on a directory and waits until the server answers a read
# of the node. Returns the process id, which is the process id of the server,
# and whether the read was answered.
sub start_script {
    my ($port, $node, @arguments) = @_;
    my $log = File::Spec->catfile($dir, "script-$port.log");
    my $pid = fork();
    defined $pid or die "fork: $!\n";
    if (!$pid) {
        open(STDOUT, '>', $log) or POSIX::_exit(126);
        open(STDERR, '>&', \*STDOUT) or POSIX::_exit(126);
        { exec { $SCRIPT } $SCRIPT, @arguments; }
        POSIX::_exit(127);
    }
    push @servers, $pid;
    my $deadline = time + $START_SECONDS;
    while (time < $deadline) {
        last if waitpid($pid, POSIX::WNOHANG()) != 0;
        return ($pid, 1, $log) if probe($port, 'read', $node) =~ /^Good /;
        sleep 0.3;
    }
    return ($pid, 0, $log);
}

sub stop_server {
    my ($pid) = @_;
    kill 'INT', $pid;
    waitpid($pid, 0);
    @servers = grep { $_ != $pid } @servers;
    return;
}

# One XML file: the server starts on the NodeSet of the directory.
{
    my ($path, $port) = new_model();
    write_nodeset(File::Spec->catfile($path, 'fixture.NodeSet2.xml'));
    my ($pid, $ready, $log) = start_script($port, $FIXTURE_NODE, $path);
    ok($ready, 'one XML file: the server starts and answers a read of a variable of the NodeSet')
        or diag(slurp($log));
    stop_server($pid);
}

# A quoted NodeId in a simulation file addresses a variable with a space.
{
    my ($path, $port) = new_model();
    my $node = "ns=2;s=demoInterface.sensors.unitA.pump's count";
    write_nodeset(File::Spec->catfile($path, 'fixture.NodeSet2.xml'));
    spew(File::Spec->catfile($path, 'simulation.conf'), "value 'ns=2;s=demoInterface.sensors.unitA.pump''s count' 17\n");
    my ($pid, $ready, $log) = start_script($port, $node, $path);
    is($ready ? probe($port, 'read', $node) : '', 'Good 17',
        'a quoted NodeId sets the value of a variable with a space') or diag(slurp($log));
    stop_server($pid);
}

# One XML file and the option --di: the DI NodeSet is loaded first, so that the
# composite model, which refers to it and holds XML files in a subdirectory,
# starts.
{
    my $path = File::Spec->catdir($dir, 'composite');
    my ($status, undef, $error) = run_command('cp', '-a', $MODEL, $path);
    is($status, 0, 'a copy of the composite model') or diag($error);
    my $port = free_port();
    spew(File::Spec->catfile($path, 'server.json5'),
        config_with_port(File::Spec->catfile($MODEL, 'server.json5'), $port));
    my ($pid, $ready, $log) = start_script($port, $COMPOSITE_NODE, '--di', $DI, $path);
    ok($ready, 'one XML file with --di: the composite model starts and answers a read')
        or diag(slurp($log));
    like(probe($port, 'read', $SIMULATOR_NODE), qr/^Good /,
        'one XML file with --di: the simulation file of the directory is used')
        or diag(slurp($log));
    stop_server($pid);
}

# A call that the script refuses: exit status 1, a message that names the cause
# and, when the directory is the cause, the directory, and no server on the
# port.
sub refused {
    my ($name, $path, $port, $pattern, @arguments) = @_;
    my ($status, $stdout, $stderr) = run_command($SCRIPT, @arguments, $path);
    is($status, 1, "$name: exit status");
    is($stdout, '', "$name: nothing on standard output");
    like($stderr, qr/\Q$path\E/, "$name: the message names the directory") if !@arguments;
    like($stderr, $pattern, "$name: the message names the cause");
    my $socket = IO::Socket::INET->new(PeerAddr => '127.0.0.1', PeerPort => $port, Proto => 'tcp');
    ok(!$socket, "$name: no server listens on the port");
    close($socket) if $socket;
    return;
}

{
    my ($path, $port) = new_model();
    refused('no XML file', $path, $port, qr/no NodeSet XML file/);
}
{
    my ($path, $port) = new_model();
    write_nodeset(File::Spec->catfile($path, 'one.NodeSet2.xml'));
    write_nodeset(File::Spec->catfile($path, 'two.NodeSet2.xml'));
    refused('two XML files', $path, $port, qr/2 XML files.*one\.NodeSet2\.xml.*two\.NodeSet2\.xml/);
}
{
    my ($path, $port) = new_model();
    write_nodeset(File::Spec->catfile($path, 'fixture.NodeSet2.xml'));
    unlink File::Spec->catfile($path, 'server.json5') or die "unlink: $!\n";
    refused('no server.json5', $path, $port, qr/holds no server\.json5/);
}
{
    my ($path, $port) = new_model();
    mkdir File::Spec->catdir($path, 'nodeset') or die "$!\n";
    write_nodeset(File::Spec->catfile($path, 'nodeset', 'fixture.NodeSet2.xml'));
    refused('an XML file only in a subdirectory', $path, $port, qr/no NodeSet XML file/);
}
{
    my ($path, $port) = new_model();
    write_nodeset(File::Spec->catfile($path, 'fixture.NodeSet2.xml'));
    refused('a missing DI file', $path, $port, qr/no-such-di\.xml is not a file/,
        '--di', File::Spec->catfile($dir, 'no-such-di.xml'));
}
{
    my ($status, $stdout, $stderr) = run_command($SCRIPT);
    is($status, 2, 'no arguments: exit status');
    like($stderr, qr/usage: run-model\.bash/, 'no arguments: the usage on standard error');
    ($status) = run_command($SCRIPT, '--no-such-option', $dir);
    is($status, 2, 'an unknown option: exit status');
    ($status) = run_command($SCRIPT, '--di');
    is($status, 2, '--di without a file: exit status');
    ($status, $stdout) = run_command($SCRIPT, '--help');
    is($status, 0, '--help: exit status');
    like($stdout, qr/usage: run-model\.bash/, '--help: the usage on standard output');
    ($status, undef, $stderr) = run_command($SCRIPT, File::Spec->catdir($dir, 'no-such-directory'));
    is($status, 1, 'a missing directory: exit status');
    like($stderr, qr/no-such-directory is not a directory/, 'a missing directory: the message names it');
}

done_testing();
