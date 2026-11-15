#!/usr/bin/env perl
#
# Writes the NodeSet2 XML file of a user-defined server interface from a JSON
# description of its tree: folders, objects, and variables in one namespace,
# each variable with a data type, an access, and a description.

use strict;
use warnings;

use Fcntl qw(O_RDONLY O_DIRECTORY);
use File::Basename qw(basename dirname);
use File::Temp qw(tempfile);
use Getopt::Long qw(GetOptionsFromArray);
use IO::Handle;
use JSON::PP;
use Pod::Usage qw(pod2usage);

# Exit statuses of the tool.
my $EXIT_OK    = 0;
my $EXIT_ERROR = 1;
my $EXIT_USAGE = 2;

# Value of the key "format" that marks a description of this tool.
my $FORMAT = 'server-interface';

# The only rule that makes a NodeId from a node: the names from the root to
# the node, joined by dots, as a string NodeId.
my $NODE_ID_RULE = 'path';
my $PATH_SEPARATOR = '.';

# Namespace index of the interface inside the NodeSet file: the only
# namespace the file declares.
my $NS = 'ns=1;';

# NodeId of the Objects folder, the parent of the root of the interface.
my $OBJECTS_FOLDER = 'i=85';

# Type definitions of the node kinds.
my %TYPE_DEFINITION = (
    folder   => 'i=61',
    object   => 'i=58',
    variable => 'i=63',
);

# Reference type from the parent to a node of each kind.
my %PARENT_REFERENCE = (
    folder   => 'Organizes',
    object   => 'HasComponent',
    variable => 'HasComponent',
);

# Data types of the description: the OPC UA type each one is written as and
# the NodeId number of that type.
my %DATA_TYPE = (
    Bool => [ 'Boolean', 1 ],
    Byte => [ 'Byte',    3 ],
    Char => [ 'Byte',    3 ],
    Int  => [ 'Int16',   4 ],
    Real => [ 'Float',   10 ],
);

# Access levels of the description.
my %ACCESS_LEVEL = (
    ro => 1,
    rw => 3,
);

# State of one run: the generated text and the NodeIds written so far.
my @out;
my %written;

# Escapes text for use in XML content and attribute values.
sub q_xml {
    my ($text) = @_;
    $text =~ s/&/&amp;/g;
    $text =~ s/</&lt;/g;
    $text =~ s/>/&gt;/g;
    $text =~ s/"/&quot;/g;
    return $text;
}

# Returns the NodeId of the node at a path of names.
sub node_id {
    my (@names) = @_;
    return $NS . 's=' . join($PATH_SEPARATOR, @names);
}

# Writes one node and, for a folder or an object, its children. @names is the
# path of names to the parent and $parent its NodeId; $root is true for the
# root of the interface, whose parent is the Objects folder.
sub write_node {
    my ($node, $names, $parent, $root, $where) = @_;
    ref $node eq 'HASH' or die "$where: a node is not an object\n";
    defined $node->{name} && !ref $node->{name} && length $node->{name}
        or die "$where: a node needs a name\n";
    my $path = join $PATH_SEPARATOR, @$names, $node->{name};
    my @path_names = (@$names, $node->{name});
    my $id = node_id(@path_names);
    !exists $written{$id} or die "$where: the NodeId of $path is used twice\n";
    $written{$id} = 1;

    my $kind;
    if (exists $node->{children}) {
        ref $node->{children} eq 'ARRAY' or die "$where: children of $path is not a list\n";
        $kind = defined $node->{kind} ? $node->{kind} : 'object';
        $kind eq 'folder' || $kind eq 'object'
            or die "$where: the kind of $path is not folder or object\n";
        !defined $node->{type} && !defined $node->{access}
            or die "$where: $path has children and a type or an access\n";
    }
    else {
        $kind = 'variable';
        !defined $node->{kind} or die "$where: the variable $path has a kind\n";
        defined $node->{type} && exists $DATA_TYPE{ $node->{type} }
            or die "$where: the type of $path is not one of "
            . join(', ', sort keys %DATA_TYPE) . "\n";
        defined $node->{access} && exists $ACCESS_LEVEL{ $node->{access} }
            or die "$where: the access of $path is not one of "
            . join(', ', sort keys %ACCESS_LEVEL) . "\n";
    }

    my $reference = $root ? 'Organizes' : $PARENT_REFERENCE{$kind};
    my $element = $kind eq 'variable' ? 'UAVariable' : 'UAObject';
    my $attrs = sprintf 'NodeId="%s" BrowseName="%s" ParentNodeId="%s"', q_xml($id),
        q_xml("1:$node->{name}"), q_xml($parent);
    if ($kind eq 'variable') {
        my $level = $ACCESS_LEVEL{ $node->{access} };
        $attrs .= sprintf ' DataType="%s" AccessLevel="%d" UserAccessLevel="%d"',
            $DATA_TYPE{ $node->{type} }[0], $level, $level;
    }
    push @out, "  <$element $attrs>\n    <DisplayName>" . q_xml($node->{name})
        . "</DisplayName>\n";
    if (defined $node->{description} && !ref $node->{description}) {
        push @out, '    <Description>' . q_xml($node->{description}) . "</Description>\n";
    }
    push @out, "    <References>\n"
        . '      <Reference ReferenceType="HasTypeDefinition">' . $TYPE_DEFINITION{$kind}
        . "</Reference>\n"
        . "      <Reference ReferenceType=\"$reference\" IsForward=\"false\">" . q_xml($parent)
        . "</Reference>\n"
        . "    </References>\n  </$element>\n";

    if ($kind ne 'variable') {
        my %names_seen;
        for my $child (@{ $node->{children} }) {
            if (ref $child eq 'HASH' && defined $child->{name}) {
                !$names_seen{ $child->{name} }++
                    or die "$where: $path has two children named $child->{name}\n";
            }
            write_node($child, \@path_names, $id, 0, $where);
        }
    }
    return;
}

# Reads a whole file as bytes.
sub read_file {
    my ($path) = @_;
    open(my $fh, '<:raw', $path) or die "$path: $!\n";
    local $/;
    my $data = <$fh>;
    close($fh) or die "$path: $!\n";
    return defined $data ? $data : '';
}

sub sync_directory {
    my ($dir) = @_;
    sysopen(my $dh, $dir, O_RDONLY | O_DIRECTORY) or die "$dir: $!\n";
    IO::Handle::sync($dh) or die "$dir: sync: $!\n";
    close($dh) or die "$dir: $!\n";
    return;
}

# Replaces a file with new content through a temporary file in the same
# directory, so the file holds the old or the new content, never a part.
sub atomic_write {
    my ($path, $data, $mode) = @_;
    my $dir = dirname($path);
    my ($fh, $tmp) = tempfile('.' . basename($path) . '.XXXXXX', DIR => $dir);
    my $done = eval {
        binmode($fh) or die "$tmp: $!\n";
        print {$fh} $data or die "$tmp: $!\n";
        $fh->flush or die "$tmp: $!\n";
        chmod($mode, $fh) or die "$tmp: $!\n";
        $fh->sync or die "$tmp: $!\n";
        close($fh) or die "$tmp: $!\n";
        rename($tmp, $path) or die "$path: $!\n";
        sync_directory($dir);
        1;
    };
    if (!$done) {
        my $error = $@;
        # Best-effort cleanup while another error is already being raised.
        unlink $tmp;
        die $error;
    }
    return;
}

# Loads the description and checks the shape of its top-level members.
sub load_description {
    my ($path) = @_;
    my $text = read_file($path);
    my $doc = eval { JSON::PP->new->utf8->relaxed->decode($text) };
    if (!defined $doc) {
        my $error = $@;
        die "$path: $error" if length $error;
        die "$path: the description is not an object\n";
    }
    ref $doc eq 'HASH' or die "$path: the description is not an object\n";
    defined $doc->{format} && $doc->{format} eq $FORMAT
        or die "$path: \"format\" is not \"$FORMAT\"\n";
    defined $doc->{namespace} && !ref $doc->{namespace} && length $doc->{namespace}
        or die "$path: \"namespace\" is not a namespace URI\n";
    defined $doc->{nodeIdRule} && $doc->{nodeIdRule} eq $NODE_ID_RULE
        or die "$path: \"nodeIdRule\" is not \"$NODE_ID_RULE\"\n";
    ref $doc->{root} eq 'HASH' && ref $doc->{root}{children} eq 'ARRAY'
        or die "$path: \"root\" is not a node with children\n";
    return $doc;
}

# Builds the NodeSet text of the description.
sub build {
    my ($doc, $path) = @_;
    @out = ();
    %written = ();
    write_node($doc->{root}, [], $OBJECTS_FOLDER, 1, $path);
    my %alias = map { $DATA_TYPE{$_}[0] => $DATA_TYPE{$_}[1] } keys %DATA_TYPE;
    my $data_type_aliases = join '', map { "    <Alias Alias=\"$_\">i=$alias{$_}</Alias>\n" }
        sort { $alias{$a} <=> $alias{$b} } keys %alias;
    my $head = qq{<?xml version="1.0" encoding="utf-8"?>\n}
        . qq{<UANodeSet xmlns="http://opcfoundation.org/UA/2011/03/UANodeSet.xsd">\n}
        . "  <NamespaceUris>\n    <Uri>" . q_xml($doc->{namespace}) . "</Uri>\n  </NamespaceUris>\n"
        . "  <Aliases>\n"
        . "    <Alias Alias=\"Organizes\">i=35</Alias>\n"
        . "    <Alias Alias=\"HasComponent\">i=47</Alias>\n"
        . "    <Alias Alias=\"HasTypeDefinition\">i=40</Alias>\n"
        . $data_type_aliases
        . "  </Aliases>\n";
    my $text = $head . join('', @out) . "</UANodeSet>\n";
    utf8::encode($text);
    return $text;
}

sub main {
    my @args = @_;
    my $output;
    my $help;
    GetOptionsFromArray(\@args, 'output|o=s' => \$output, 'help|h' => \$help)
        or return $EXIT_USAGE;
    if ($help) {
        pod2usage(-exitval => 'NOEXIT', -verbose => 1, -output => \*STDOUT);
        return $EXIT_OK;
    }
    if (@args != 1) {
        pod2usage(-exitval => 'NOEXIT', -verbose => 0, -output => \*STDERR);
        return $EXIT_USAGE;
    }

    my $doc = load_description($args[0]);
    my $text = build($doc, $args[0]);
    if (defined $output) {
        atomic_write($output, $text, 0644);
    }
    else {
        binmode(STDOUT) or die "stdout: $!\n";
        print {*STDOUT} $text or die "stdout: $!\n";
    }
    return $EXIT_OK;
}

my $status;
eval {
    $status = main(@ARGV);
    defined $status or die "internal error: main returned no exit status\n";
    1;
} or do {
    my $error = $@;
    print STDERR "server-interface-nodeset: $error";
    $status = $EXIT_ERROR;
};
exit $status;

__END__

=head1 NAME

server-interface-nodeset.pl - write the NodeSet2 XML file of a user-defined server interface

=head1 SYNOPSIS

server-interface-nodeset.pl [--output <file>] <description.json>

server-interface-nodeset.pl --help

=head1 OPTIONS

=over 4

=item B<--output>, B<-o> <file>

Write the NodeSet to this file. The file is replaced only when the whole
NodeSet was built. Without the option the NodeSet goes to standard output.

=item B<--help>, B<-h>

Print this help.

=back

=head1 DESCRIPTION

The description is a JSON object. Comments that start with C<#> and a comma
after the last element are accepted.

=over 4

=item C<format>

The text C<server-interface>.

=item C<namespace>

The namespace URI of the interface. The NodeSet declares it as its only
namespace.

=item C<nodeIdRule>

The rule that makes a NodeId from a node. The only rule is C<path>: the string
NodeId is the names from the root to the node, joined by dots.

=item C<root>

The root node of the interface, an object below the Objects folder.

=back

A node has C<name>. A node with C<children>, a list of nodes, is a folder or
an object: C<kind> is C<folder> or C<object>, and C<object> is the default. A
node without C<children> is a variable with C<type> (C<Bool>, C<Byte>, C<Char>,
C<Int>, or C<Real>, written as Boolean, Byte, Byte, Int16, and Float), C<access>
(C<ro> for read, C<rw> for read and write), and optionally C<description>. A
variable has no value in the NodeSet.

=head1 EXIT STATUS

0 when the NodeSet was written, 1 on an error in the description or in file
access, 2 on a usage error.

=cut
