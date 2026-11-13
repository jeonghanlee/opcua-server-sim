#!/usr/bin/env perl
#
# Command-line cases of tools/simatic-nodeset.pl. Each case runs the tool as
# a subprocess; the description of the shipped model is the main fixture.

use strict;
use warnings;

use Cwd qw(abs_path);
use File::Basename qw(dirname);
use File::Spec;
use File::Temp qw(tempdir);
use POSIX ();
use Test::More;

my $TOP   = abs_path(File::Spec->catdir(dirname(__FILE__), File::Spec->updir));
my $TOOL  = File::Spec->catfile($TOP, 'tools', 'simatic-nodeset.pl');
my $MODEL = File::Spec->catdir($TOP, 'models', 's7-1500-composite');
my $DESCRIPTION = File::Spec->catfile($MODEL, 'plc.json');
my $NODESET     = File::Spec->catfile($MODEL, 's7-1500-composite.NodeSet2.xml');

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

# Decodes base64 text without line breaks.
sub unbase64 {
    my ($text) = @_;
    my %value;
    my $i = 0;
    $value{$_} = $i++ for ('A' .. 'Z', 'a' .. 'z', '0' .. '9', '+', '/');
    my $bytes = '';
    $text =~ tr/=//d;
    my ($bits, $count) = (0, 0);
    for my $char (split //, $text) {
        $bits = ($bits << 6) | $value{$char};
        $count += 6;
        if ($count >= 8) {
            $count -= 8;
            $bytes .= chr(($bits >> $count) & 255);
        }
    }
    return $bytes;
}

my $dir = tempdir(CLEANUP => 1);
my $shipped = slurp($NODESET);

# The shipped NodeSet is what the tool writes from the shipped description.
{
    my $target = File::Spec->catfile($dir, 'out.xml');
    my ($status, $stdout, $stderr) = run_tool('--output', $target, $DESCRIPTION);
    is($status, 0,  'model: exit status');
    is($stdout, '', 'model: nothing on stdout with --output');
    is($stderr, '', 'model: nothing on stderr');
    ok(slurp($target) eq $shipped, 'model: output equals the shipped NodeSet');
    is((stat $target)[2] & 07777, 0644, 'model: mode of the output file');
}

{
    my ($status, $stdout) = run_tool($DESCRIPTION);
    is($status, 0, 'stdout: exit status');
    ok($stdout eq $shipped, 'stdout: output equals the shipped NodeSet');
}

# The dictionary the tool writes decodes to the schema of all structures.
{
    my (undef, $generated) = run_tool($DESCRIPTION);
    my ($encoded) = $generated =~ m{<uax:ByteString>([A-Za-z0-9+/=]+)</uax:ByteString>};
    ok(defined $encoded, 'dictionary: present');
    my $schema = unbase64($encoded // '');
    like($schema, qr/\A<\?xml version="1\.0" encoding="utf-8"\?><opc:TypeDictionary /,
        'dictionary: starts with the schema element');
    like($schema, qr{</opc:TypeDictionary>\z}, 'dictionary: complete');
    like($schema, qr/Name="udtArrayChar_Size" \/><opc:Field TypeName="opc:Byte" Name="udtArrayChar" LengthField="udtArrayChar_Size"/,
        'dictionary: an array field follows its length field');
}

{
    my ($status, $stdout, $stderr) = run_tool('--help');
    is($status, 0, 'help: exit status');
    like($stdout, qr/--output/, 'help: names the output option');
    is($stderr, '', 'help: nothing on stderr');
}

{
    my ($status, $stdout, $stderr) = run_tool();
    is($status, 2,  'no arguments: exit status');
    is($stdout, '', 'no arguments: nothing on stdout');
    like($stderr, qr/description\.json/, 'no arguments: usage on stderr');
}

{
    my ($status) = run_tool('--unknown', $DESCRIPTION);
    is($status, 2, 'unknown option: exit status');
}

# Errors leave an existing output file untouched.
my $SECTIONS = '"sections": ["@blocks"], "types": {"Int": {"alias": "Int16", "builtin": "Int16"}}';
my @errors = (
    { name => 'missing description', file => undef, stderr => qr/missing\.json/ },
    { name => 'malformed JSON', text => '{ "sections": [', stderr => qr/broken\.json/ },
    { name => 'JSON null', text => 'null', stderr => qr/broken\.json: the description is not an object/ },
    { name => 'unknown data type',
      text => "{ $SECTIONS, \"blocks\": [{\"name\": \"DB\", \"area\": \"DataBlocksGlobal\","
          . " \"comment\": \"c\", \"tags\": [{\"name\": \"x\", \"type\": \"Nope\"}]}] }",
      stderr => qr/unknown data type "Nope"/ },
    { name => 'missing section file',
      text => '{ "sections": ["absent.xml"], "types": {} }', stderr => qr/absent\.xml/ },
    { name => 'block without area',
      text => "{ $SECTIONS, \"blocks\": [{\"name\": \"DB\", \"comment\": \"c\"}] }",
      stderr => qr/no area/ },
);
for my $case (@errors) {
    my $path = File::Spec->catfile($dir, defined $case->{text} ? 'broken.json' : 'missing.json');
    spew($path, $case->{text}) if defined $case->{text};
    my $target = File::Spec->catfile($dir, 'keep.xml');
    spew($target, "previous\n");
    my ($status, $stdout, $stderr) = run_tool('--output', $target, $path);
    is($status, 1,  "$case->{name}: exit status");
    is($stdout, '', "$case->{name}: nothing on stdout");
    like($stderr, $case->{stderr}, "$case->{name}: message");
    unlike($stderr, qr/(\S+\.json): \1/, "$case->{name}: the path is named once");
    is(slurp($target), "previous\n", "$case->{name}: output file unchanged");
}

# A description with a comment, a trailing comma, a flat block, a start
# value that needs escaping, and a read-only tag.
{
    my $path = File::Spec->catfile($dir, 'small.json');
    spew($path, <<'JSON');
{
  # one block
  "sections": ["@blocks", "@memory"],
  "types": {
    "Int": {"alias": "Int16", "builtin": "Int16"},
    "String": {"alias": "STRING", "builtin": "String"},
  },
  "blocks": [
    {"name": "DB 1", "area": "DataBlocksGlobal", "comment": "c", "flat": true,
     "tags": [{"name": "A", "type": "Int", "start": 0, "access": 1},
              {"name": "B", "type": "String", "start": "a<b&c"},
              {"name": "C", "type": "Int", "length": 2, "start": [7]}]}
  ],
  "memory": [{"name": "M", "type": "Int"}]
}
JSON
    my ($status, $stdout, $stderr) = run_tool($path);
    is($status, 0, 'small: exit status');
    is($stderr, '', 'small: nothing on stderr');
    like($stdout, qr/NodeId="ns=1;s=&quot;DB 1&quot;\.A" BrowseName="1:A" [^>]*AccessLevel="1" UserAccessLevel="1">/,
        'small: flat member NodeId and read-only access');
    like($stdout, qr{<uax:Int16>0</uax:Int16>}, 'small: start value zero is written');
    like($stdout, qr{<uax:String>a&lt;b&amp;c</uax:String>}, 'small: start value is escaped');
    like($stdout, qr/NodeId="ns=1;s=&quot;DB 1&quot;\.C\[0\]"[^>]*>\s*<DisplayName>0<.*?<uax:Int16>7</s,
        'small: first array element carries its start value');
    unlike($stdout, qr/C\[1\]"[^>]*>\s*<DisplayName>1<\/DisplayName>\s*<References>.*?<\/References>\s*<Value>/s,
        'small: second array element has no start value');
    like($stdout, qr/NodeId="ns=1;s=&quot;M&quot;"[^>]*>.*?ReferenceType="Organizes" IsForward="false">ns=1;s=Memory</s,
        'small: memory tag below the Memory area');
    like($stdout, qr{</UANodeSet>\n\z}, 'small: closing tag');
}

done_testing();
