#!/usr/bin/env perl
#
# Cases of tools/server-interface-nodeset.pl. Each case runs the tool as a
# subprocess on the generic description in t/fixtures/interface.json. The
# last cases start the built server on the written NodeSet and check it with
# the built opcua-probe client; "make test" builds the binaries and names them
# in SIM_SERVER and SIM_PROBE.

use strict;
use warnings;

use Cwd qw(abs_path);
use File::Basename qw(dirname);
use File::Spec;
use File::Temp qw(tempdir);
use IO::Socket::INET;
use JSON::PP;
use POSIX ();
use Test::More;
use Time::HiRes qw(sleep time);

my $TOP     = abs_path(File::Spec->catdir(dirname(__FILE__), File::Spec->updir));
my $TOOL    = File::Spec->catfile($TOP, 'tools', 'server-interface-nodeset.pl');
my $FIXTURE = File::Spec->catfile($TOP, 't', 'fixtures', 'interface.json');
my ($SERVER, $PROBE) = @ENV{qw(SIM_SERVER SIM_PROBE)};

# Seconds to wait for the server to answer and for one probe command.
my $START_SECONDS   = 20;
my $COMMAND_SECONDS = 30;

# Namespace URI of the fixture and the namespace index the server gives it
# when it is the only NodeSet that the server loads.
my $NAMESPACE   = 'urn:example:server-interface';
my $SERVER_NS   = 2;
my $PROBE_FIRST = "ns=$SERVER_NS;s=demoInterface.sensors.unitA.flag";

# The nodes the description of the fixture states, in the order of the
# description: path, kind, OPC UA type, access level, and description.
my @NODES = (
    [ 'demoInterface',                  'object' ],
    [ 'demoInterface.sensors',          'folder' ],
    [ 'demoInterface.sensors.unitA',    'object' ],
    [ 'demoInterface.sensors.unitA.flag',  'variable', 'Boolean', 1, 'Flag of the unit' ],
    [ 'demoInterface.sensors.unitA.level', 'variable', 'Float',   1, 'Level of the unit' ],
    [ 'demoInterface.sensors.unitA.count', 'variable', 'Int16',   1, 'Count of the unit' ],
    [ 'demoInterface.sensors.unitA.label', 'variable', 'Byte',    1, 'Label of the unit' ],
    [ 'demoInterface.settings',         'folder' ],
    [ 'demoInterface.settings.setpoint', 'variable', 'Float',   3, 'Setpoint' ],
    [ 'demoInterface.settings.enable',   'variable', 'Boolean', 3, 'Enable' ],
    [ 'demoInterface.settings.mode',     'variable', 'Byte',    3, 'Mode' ],
);
my %TYPE_DEFINITION = (folder => 'i=61', object => 'i=58', variable => 'i=63');
my %PARENT_REFERENCE = (folder => 'Organizes', object => 'HasComponent', variable => 'HasComponent');

my $dir = tempdir(CLEANUP => 1);
my @servers;
END {
    for my $pid (@servers) {
        kill 'INT', $pid;
        waitpid($pid, 0);
    }
}

sub run_tool {
    my (@args) = @_;
    my $err = File::Temp->new;
    my $pid = open(my $out, '-|');
    defined $pid or die "fork: $!\n";
    if (!$pid) {
        open(STDERR, '>&', $err) or POSIX::_exit(126);
        $ENV{LC_ALL} = 'C';
        delete $ENV{LANGUAGE};
        { exec { $^X } $^X, $TOOL, @args; }
        POSIX::_exit(127);
    }
    my $stdout = do { local $/; <$out> };
    close($out);
    my $status = ($? & 127) ? 'signal ' . ($? & 127) : $? >> 8;
    seek($err, 0, 0);
    my $stderr = do { local $/; <$err> };
    return ($status, defined $stdout ? $stdout : '', defined $stderr ? $stderr : '');
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

# Returns the text of the fixture after a change of its decoded structure.
sub fixture_edited {
    my ($change) = @_;
    my $doc = JSON::PP->new->utf8->relaxed->decode(slurp($FIXTURE));
    $change->($doc);
    return JSON::PP->new->utf8->canonical->encode($doc);
}

# Returns the node of the fixture at a path of names below the root.
sub fixture_node {
    my ($doc, @names) = @_;
    my $node = $doc->{root};
    for my $name (@names) {
        ($node) = grep { $_->{name} eq $name } @{ $node->{children} };
    }
    return $node;
}

# Splits the NodeSet into its node elements and returns a hash that maps each
# NodeId to the attributes, the type definition, the parent reference type,
# and the description of the node.
sub parse_nodes {
    my ($xml) = @_;
    my %node;
    while ($xml =~ m{<(UAObject|UAVariable) ([^>]*)>(.*?)</\1>}gs) {
        my ($element, $attrs, $body) = ($1, $2, $3);
        my %attr = $attrs =~ /(\w+)="([^"]*)"/g;
        my ($definition) = $body =~ m{<Reference ReferenceType="HasTypeDefinition">([^<]*)</Reference>};
        my ($reference) = $body =~ m{<Reference ReferenceType="(\w+)" IsForward="false">};
        my ($description) = $body =~ m{<Description>([^<]*)</Description>};
        my ($value) = $body =~ m{(<Value>)};
        $node{ $attr{NodeId} } = {
            %attr,
            element     => $element,
            definition  => $definition,
            reference   => $reference,
            description => $description,
            value       => $value,
        };
    }
    return \%node;
}

# T1: the NodeSet holds the nodes of the description with the stated attributes.
my $nodeset_path = File::Spec->catfile($dir, 'fixture.NodeSet2.xml');
my ($status, $stdout, $stderr) = run_tool('--output', $nodeset_path, $FIXTURE);
is($status, 0, 'a valid description: exit status');
is($stdout, '', 'a valid description: nothing on standard output');
is($stderr, '', 'a valid description: nothing on standard error');
my $xml = -f $nodeset_path ? slurp($nodeset_path) : '';
my $nodes = parse_nodes($xml);

is_deeply([ sort keys %$nodes ], [ sort map { "ns=1;s=$_->[0]" } @NODES ],
    'the NodeSet holds exactly the NodeIds of the description, made by the path rule');
like($xml, qr{<NamespaceUris>\s*<Uri>\Q$NAMESPACE\E</Uri>\s*</NamespaceUris>},
    'the NodeSet declares the namespace URI of the description as its only namespace');
for my $spec (@NODES) {
    my ($path, $kind, $type, $access, $description) = @$spec;
    my $node = $nodes->{"ns=1;s=$path"} || {};
    my ($parent) = $path =~ /^(.*)\.[^.]+$/;
    my ($name)   = $path =~ /([^.]+)$/;
    is($node->{BrowseName}, "1:$name", "$path: browse name");
    is($node->{ParentNodeId}, defined $parent ? "ns=1;s=$parent" : 'i=85', "$path: parent");
    is($node->{definition}, $TYPE_DEFINITION{$kind}, "$path: type definition");
    is($node->{reference}, defined $parent ? $PARENT_REFERENCE{$kind} : 'Organizes',
        "$path: reference type from the parent");
    if ($kind eq 'variable') {
        is($node->{element}, 'UAVariable', "$path: element");
        is($node->{DataType}, $type, "$path: data type");
        is($node->{AccessLevel}, $access, "$path: access level");
        is($node->{UserAccessLevel}, $access, "$path: user access level");
        is($node->{description}, $description, "$path: description");
        ok(!defined $node->{value}, "$path: no value in the NodeSet");
    }
    else {
        is($node->{element}, 'UAObject', "$path: element");
    }
}
is_deeply([ sort grep { !/^(Organizes|HasComponent|HasTypeDefinition)$/ } $xml =~ /<Alias Alias="(\w+)">/g ],
    [ qw(Boolean Byte Float Int16) ], 'the aliases of the data types');
{
    my @entries = grep { $_ ne '.' && $_ ne '..' } do {
        opendir(my $dh, $dir) or die "$dir: $!\n";
        readdir($dh);
    };
    is_deeply([ sort @entries ], ['fixture.NodeSet2.xml'], 'the output directory holds only the output file');
    is(sprintf('%04o', (stat $nodeset_path)[2] & 07777), '0644', 'mode of the output file');
}
{
    my ($to_stdout_status, $to_stdout) = run_tool($FIXTURE);
    is($to_stdout_status, 0, 'without --output: exit status');
    is($to_stdout, $xml, 'without --output: standard output holds the same NodeSet');
}

# T2: an error in the description or in the arguments gives the status of its
# kind, a message that names the cause, and no output file.
my @errors = (
    [ 'malformed JSON', sub { 'not json' }, qr/malformed|expected|unexpected/i ],
    [ 'not an object', sub { '[]' }, qr/not an object/ ],
    [ 'wrong format', sub { fixture_edited(sub { $_[0]{format} = 'other' }) }, qr/"format"/ ],
    [ 'no namespace', sub { fixture_edited(sub { delete $_[0]{namespace} }) }, qr/"namespace"/ ],
    [ 'unknown NodeId rule', sub { fixture_edited(sub { $_[0]{nodeIdRule} = 'number' }) }, qr/"nodeIdRule"/ ],
    [ 'unknown type',
      sub { fixture_edited(sub { fixture_node($_[0], 'settings', 'setpoint')->{type} = 'Word' }) },
      qr/type of demoInterface\.settings\.setpoint/ ],
    [ 'unknown access',
      sub { fixture_edited(sub { fixture_node($_[0], 'settings', 'setpoint')->{access} = 'x' }) },
      qr/access of demoInterface\.settings\.setpoint/ ],
    [ 'duplicate sibling',
      sub { fixture_edited(sub { fixture_node($_[0], 'settings', 'enable')->{name} = 'setpoint' }) },
      qr/two children named setpoint/ ],
    [ 'a name with a dot that gives the NodeId of another node',
      sub {
          fixture_edited(sub {
              push @{ fixture_node($_[0], 'sensors')->{children} },
                  { name => 'unitA.flag', type => 'Bool', access => 'ro' };
          });
      },
      qr/NodeId of demoInterface\.sensors\.unitA\.flag is used twice/ ],
    [ 'unknown kind',
      sub { fixture_edited(sub { fixture_node($_[0], 'sensors')->{kind} = 'tree' }) },
      qr/kind of demoInterface\.sensors/ ],
);
my $existing = File::Spec->catfile($dir, 'existing.xml');
for my $case (@errors) {
    my ($name, $make, $pattern) = @$case;
    my $description = File::Spec->catfile($dir, 'bad.json');
    spew($description, $make->());
    spew($existing, "old content\n");
    my ($bad_status, $bad_stdout, $bad_stderr) = run_tool('--output', $existing, $description);
    is($bad_status, 1, "$name: exit status");
    is($bad_stdout, '', "$name: nothing on standard output");
    like($bad_stderr, $pattern, "$name: the message names the cause");
    is(slurp($existing), "old content\n", "$name: an existing output file is not changed");
}
{
    my $missing = File::Spec->catfile($dir, 'missing.json');
    my ($s, undef, $e) = run_tool('--output', File::Spec->catfile($dir, 'never.xml'), $missing);
    is($s, 1, 'a missing description file: exit status');
    like($e, qr/\Q$missing\E/, 'a missing description file: the message names the file');
    ok(!-e File::Spec->catfile($dir, 'never.xml'), 'a missing description file: no output file');
}
{
    my ($s, $o, $e) = run_tool();
    is($s, 2, 'no arguments: exit status');
    is($o, '', 'no arguments: nothing on standard output');
    like($e, qr/SYNOPSIS|server-interface-nodeset/i, 'no arguments: the usage on standard error');
    ($s) = run_tool('--no-such-option', $FIXTURE);
    is($s, 2, 'an unknown option: exit status');
    ($s) = run_tool($FIXTURE, $FIXTURE);
    is($s, 2, 'two descriptions: exit status');
    ($s, $o) = run_tool('--help');
    is($s, 0, '--help: exit status');
    like($o, qr/--output/, '--help: the options on standard output');
}

# T3: the server loads the NodeSet and serves the variables with their type and
# access.
SKIP: {
    skip 'run "make test": SIM_SERVER and SIM_PROBE name the built binaries', 22
        if !defined $SERVER || !defined $PROBE || !-x $SERVER || !-x $PROBE;

    my $port = do {
        my $socket = IO::Socket::INET->new(Listen => 1, LocalAddr => '127.0.0.1', LocalPort => 0, Proto => 'tcp')
            or die "free port: $!\n";
        my $number = $socket->sockport;
        close($socket);
        $number;
    };
    my $config = File::Spec->catfile($dir, 'server.json5');
    spew($config, qq{{ serverUrls: ["opc.tcp://:$port"], maxSessions: 4, }\n});
    my $log = File::Spec->catfile($dir, 'server.log');

    my $probe = sub {
        my (@args) = @_;
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
    };

    my $pid = fork();
    defined $pid or die "fork: $!\n";
    if (!$pid) {
        open(STDOUT, '>', $log) or POSIX::_exit(126);
        open(STDERR, '>&', \*STDOUT) or POSIX::_exit(126);
        { exec { $SERVER } $SERVER, $config, $nodeset_path; }
        POSIX::_exit(127);
    }
    push @servers, $pid;
    my $ready = 0;
    my $deadline = time + $START_SECONDS;
    while (time < $deadline) {
        last if waitpid($pid, POSIX::WNOHANG()) != 0;
        if ($probe->('read', $PROBE_FIRST) =~ /^Good /) {
            $ready = 1;
            last;
        }
        sleep 0.3;
    }
    ok($ready, 'the server loads the NodeSet and answers a read')
        or diag(slurp($log));

    my %zero = (Boolean => 'false', Float => '0.0', Int16 => '0', Byte => '0');
    my %write = (Boolean => [ 'bool', 'true', 'true' ], Float => [ 'float', '2.5', '2.5' ],
        Byte => [ 'byte', '7', '7' ]);
    my %probe_type = (Boolean => 'bool', Float => 'float', Int16 => 'int16', Byte => 'byte');
    for my $spec (grep { $_->[1] eq 'variable' } @NODES) {
        my ($path, undef, $type, $access) = @$spec;
        my $node = "ns=$SERVER_NS;s=$path";
        is($probe->('read', $node), "Good $zero{$type}", "$path: the zero value of the type");
        if ($access == 1) {
            is($probe->('write', $node, $probe_type{$type}, $type eq 'Boolean' ? 'true' : '1'),
                'BadNotWritable', "$path: a write is refused");
            is($probe->('read', $node), "Good $zero{$type}", "$path: the value is unchanged after the refused write");
        }
        else {
            my ($probe_name, $value, $read) = @{ $write{$type} };
            is($probe->('write', $node, $probe_name, $value), 'Good', "$path: a write is accepted");
            is($probe->('read', $node), "Good $read", "$path: the written value is read back");
        }
    }
    kill 'INT', $pid;
    waitpid($pid, 0);
    @servers = grep { $_ != $pid } @servers;
}

done_testing();
