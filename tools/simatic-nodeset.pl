#!/usr/bin/env perl
#
# Writes the NodeSet2 XML file of a SIMATIC standard server interface from a
# JSON description of the PLC program: structures, data blocks, tags, method
# instances, and memory tags. Fixed parts of the NodeSet come from XML
# section files named by the description.

use strict;
use warnings;

use Fcntl qw(O_RDONLY O_DIRECTORY);
use File::Basename qw(basename dirname);
use File::Spec;
use File::Temp qw(tempfile);
use Getopt::Long qw(GetOptionsFromArray);
use IO::Handle;
use JSON::PP;
use Pod::Usage qw(pod2usage);

# Exit statuses of the tool.
my $EXIT_OK    = 0;
my $EXIT_ERROR = 1;
my $EXIT_USAGE = 2;

# Namespace index of the SIMATIC namespace inside the NodeSet file.
my $NS = 'ns=1;';

# Numeric NodeIds of the SIMATIC namespace that generated nodes refer to.
my $ID_USER_STRUCTURES   = 3400;
my $ID_SYSTEM_STRUCTURES = 3500;
my $ID_STRUCTURES_TYPE   = 2400;
my $ID_DICTIONARY        = 6001;
my $ID_BLOCK_TYPE        = 1003;

# Folders of an instance data block in the order they are written, each with
# the reference type that connects the folder and its tags.
my @BLOCK_FOLDERS = (
    [ 'Inputs',  4003 ],
    [ 'Outputs', 4004 ],
    [ 'InOuts',  4002 ],
    [ 'Static',  4005 ],
);

# Area folder of the memory tags.
my $MEMORY_AREA = 'Memory';

# Placeholder in a section file that receives the binary type dictionary.
my $DICTIONARY_PLACEHOLDER = '@TYPE_DICTIONARY@';

# Namespace URI of the SIMATIC namespace, the target of the type dictionary.
my $SIMATIC_URI = 'http://www.siemens.com/simatic-s7-opcua';

# NodeId numbers of the OPC UA built-in data types used in method arguments.
my %BUILTIN_ID = (
    Boolean => 1,  SByte  => 2,  Byte   => 3,  Int16  => 4, UInt16 => 5,
    Int32   => 6,  UInt32 => 7,  Int64  => 8,  UInt64 => 9, Float  => 10,
    Double  => 11, String => 12, DateTime => 13,
);

my $ACCESS_READ_WRITE = 3;

# State of one run: the decoded description and the generated text.
my %types;
my %structures;
my @structure_order;
my %block_types_written;
my @out;

# Escapes text for use in XML content and attribute values.
sub q_xml {
    my ($text) = @_;
    $text =~ s/&/&amp;/g;
    $text =~ s/</&lt;/g;
    $text =~ s/>/&gt;/g;
    $text =~ s/"/&quot;/g;
    return $text;
}

# Escapes text for use in XML content only.
sub q_content {
    my ($text) = @_;
    $text =~ s/&/&amp;/g;
    $text =~ s/</&lt;/g;
    $text =~ s/>/&gt;/g;
    return $text;
}

sub is_structure {
    my ($type) = @_;
    return exists $structures{$type};
}

sub structure_id {
    my ($type) = @_;
    return $NS . 's=DT_' . $type;
}

# Returns the DataType attribute of a tag: the NodeId of a structure or the
# alias of a SIMATIC data type.
sub data_type {
    my ($type) = @_;
    return structure_id($type) if is_structure($type);
    exists $types{$type} or die "unknown data type \"$type\"\n";
    return $types{$type}{alias};
}

# Returns the type definition of a Variable that holds one structure.
sub structure_type_definition {
    my ($type) = @_;
    return $structures{$type}{variableType} ? $NS . 's=VT_' . $type : 'i=63';
}

# Returns the name part of a browse name "<index>:<name>".
sub display_name {
    my ($browse) = @_;
    my (undef, $name) = split /:/, $browse, 2;
    return defined $name ? $name : $browse;
}

# Returns the Value element of a scalar start value.
sub value_xml {
    my ($type, $value) = @_;
    my $builtin = $types{$type}{builtin};
    if ($builtin eq 'Boolean') {
        $value = $value ? 'true' : 'false';
    }
    return "    <Value>\n      <uax:$builtin>" . q_content("$value")
        . "</uax:$builtin>\n    </Value>\n";
}

# Writes one Variable node. %option: rank and dims for an array, access for
# the access level, value for a Value element.
sub variable {
    my ($node, $browse, $parent, $dtype, $typedef, $ref, %option) = @_;
    my $attrs = sprintf 'NodeId="%s" BrowseName="%s" ParentNodeId="%s" DataType="%s"',
        q_xml($node), q_xml($browse), q_xml($parent), q_xml($dtype);
    if (defined $option{rank}) {
        $attrs .= sprintf ' ValueRank="%d" ArrayDimensions="%d"', $option{rank}, $option{dims};
    }
    if (defined $option{access}) {
        $attrs .= sprintf ' AccessLevel="%d" UserAccessLevel="%d"', $option{access},
            $option{access};
    }
    push @out, "  <UAVariable $attrs>\n    <DisplayName>" . q_xml(display_name($browse))
        . "</DisplayName>\n";
    push @out, "    <References>\n"
        . '      <Reference ReferenceType="HasTypeDefinition">' . q_xml($typedef)
        . "</Reference>\n"
        . "      <Reference ReferenceType=\"$ref\" IsForward=\"false\">" . q_xml($parent)
        . "</Reference>\n"
        . "    </References>\n";
    push @out, $option{value} if defined $option{value};
    push @out, "  </UAVariable>\n";
    return;
}

# Writes one Object node.
sub object {
    my ($node, $browse, $parent, $typedef, $ref) = @_;
    push @out, sprintf "  <UAObject NodeId=\"%s\" BrowseName=\"%s\" ParentNodeId=\"%s\">\n"
        . "    <DisplayName>%s</DisplayName>\n",
        q_xml($node), q_xml($browse), q_xml($parent), q_xml(display_name($browse));
    push @out, "    <References>\n"
        . '      <Reference ReferenceType="HasTypeDefinition">' . q_xml($typedef)
        . "</Reference>\n"
        . "      <Reference ReferenceType=\"$ref\" IsForward=\"false\">" . q_xml($parent)
        . "</Reference>\n"
        . "    </References>\n  </UAObject>\n";
    return;
}

# Checks one tag or field of the description and fills in its defaults.
sub tag_fields {
    my ($tag, $where) = @_;
    ref $tag eq 'HASH' or die "$where: a tag is not an object\n";
    for my $key (qw(name type)) {
        defined $tag->{$key} && !ref $tag->{$key} && length $tag->{$key}
            or die "$where: a tag has no $key\n";
    }
    my $length = $tag->{length} // 0;
    !ref $length && $length =~ /\A[0-9]+\z/ or die "$where: length of \"$tag->{name}\"\n";
    my $access = $tag->{access} // $ACCESS_READ_WRITE;
    !ref $access && $access =~ /\A[0-9]+\z/ or die "$where: access of \"$tag->{name}\"\n";
    return ($tag->{name}, $tag->{type}, $length, $tag->{start}, $access);
}

# Writes one tag with its element and member Variables. An array has one
# Variable per element below it; a structure has one Variable per member.
# Start values go to the scalar Variables only.
sub tag {
    my ($node, $name, $parent, $ref, $type, $count, $start, $access) = @_;
    my $browse = '1:' . $name;

    if (!$count && !is_structure($type) && exists $types{$type}
        && $types{$type}{length}) {
        variable($node, $browse, $parent, data_type($type), 'i=63', $ref,
            rank => 1, dims => $types{$type}{length}, access => $access);
        return;
    }

    if ($count) {
        my $typedef = is_structure($type) ? 'i=62' : 'i=63';
        variable($node, $browse, $parent, data_type($type), $typedef, $ref,
            rank => 1, dims => $count, access => $access);
        for my $i (0 .. $count - 1) {
            my $element_start = (ref $start eq 'ARRAY' && $i < @{$start}) ? $start->[$i] : undef;
            tag("$node\[$i\]", "$i", $node, 'HasComponent', $type, 0, $element_start, $access);
        }
        return;
    }

    if (is_structure($type)) {
        my $spec = $structures{$type};
        variable($node, $browse, $parent, structure_id($type),
            structure_type_definition($type), $ref, access => $access);
        for my $field (@{ $spec->{fields} }) {
            my ($m_name, $m_type, $m_count, $m_default) = tag_fields($field, "structure $type");
            my $m_start = ref $start eq 'HASH' ? $start->{$m_name} : undef;
            $m_start = $m_default if !defined $m_start;
            tag("$node.\"$m_name\"", $m_name, $node, 'HasComponent', $m_type, $m_count,
                $m_start, $spec->{memberAccess} // $access);
        }
        return;
    }

    my $value = defined $start ? value_xml($type, $start) : undef;
    variable($node, $browse, $parent, data_type($type), 'i=63', $ref,
        access => $access, value => $value);
    return;
}

# Writes the type nodes of every structure the description defines: the
# DataType with its definition, the encoding Object, the dictionary entry,
# and the VariableType with one Variable per member.
sub structure_types {
    push @out, "  <!-- Structures of the user program and of the method instances, each with\n"
        . "       its encoding node, dictionary entry, and VariableType -->\n";
    for my $type (@structure_order) {
        my $spec = $structures{$type};
        next if $spec->{existing};
        my $browse = '1:' . ($spec->{browseName} // $type);
        my $base = 'i=' . ($spec->{system} ? $ID_SYSTEM_STRUCTURES : $ID_USER_STRUCTURES);
        my $id = structure_id($type);

        push @out, sprintf "  <UADataType NodeId=\"%s\" BrowseName=\"%s\">\n"
            . "    <DisplayName>%s</DisplayName>\n"
            . "    <References>\n"
            . "      <Reference ReferenceType=\"HasSubtype\" IsForward=\"false\">%s%s</Reference>\n"
            . "      <Reference ReferenceType=\"HasEncoding\">%ss=TE_%s</Reference>\n"
            . "    </References>\n    <Definition Name=\"%s\">\n",
            q_xml($id), q_xml($browse), q_xml(display_name($browse)), $NS, $base, $NS,
            q_xml($type), q_xml('1:' . $type);
        for my $field (@{ $spec->{fields} }) {
            my ($m_name, $m_type, $m_count) = tag_fields($field, "structure $type");
            push @out, sprintf "      <Field Name=\"%s\" DataType=\"%s\"%s/>\n",
                q_xml($m_name), q_xml(data_type($m_type)), $m_count ? ' ValueRank="1"' : '';
        }
        push @out, "    </Definition>\n  </UADataType>\n";

        push @out, sprintf "  <UAObject NodeId=\"%ss=TE_%s\" BrowseName=\"Default Binary\">\n"
            . "    <DisplayName>Default Binary</DisplayName>\n    <References>\n"
            . "      <Reference ReferenceType=\"HasTypeDefinition\">i=76</Reference>\n"
            . "      <Reference ReferenceType=\"HasEncoding\" IsForward=\"false\">%s</Reference>\n"
            . "      <Reference ReferenceType=\"HasDescription\">%ss=TD_%s</Reference>\n"
            . "    </References>\n  </UAObject>\n",
            $NS, q_xml($type), q_xml($id), $NS, q_xml($type);

        variable($NS . 's=TD_' . $type, '1:' . $type, $NS . 'i=' . $ID_DICTIONARY, 'String',
            'i=69', 'HasComponent',
            value => "    <Value>\n      <uax:String>" . q_xml($type)
                . "</uax:String>\n    </Value>\n");

        next if !$spec->{variableType};
        my $vt = $NS . 's=VT_' . $type;
        push @out, sprintf "  <UAVariableType NodeId=\"%s\" BrowseName=\"%s\" DataType=\"%s\">\n"
            . "    <DisplayName>%s</DisplayName>\n    <References>\n"
            . "      <Reference ReferenceType=\"HasSubtype\" IsForward=\"false\">%si=%d</Reference>\n"
            . "    </References>\n  </UAVariableType>\n",
            q_xml($vt), q_xml($browse), q_xml($id), q_xml(display_name($browse)), $NS,
            $ID_STRUCTURES_TYPE;
        for my $field (@{ $spec->{fields} }) {
            my ($m_name, $m_type, $m_count) = tag_fields($field, "structure $type");
            my %shape;
            my $typedef;
            if ($m_count) {
                $typedef = is_structure($m_type) ? 'i=62' : 'i=63';
                %shape = (rank => 1, dims => $m_count);
            }
            else {
                $typedef = is_structure($m_type) ? structure_type_definition($m_type) : 'i=63';
            }
            variable("${NS}s=V_$type.\"$m_name\"", '1:' . $m_name, $vt, data_type($m_type),
                $typedef, 'HasComponent', %shape);
        }
    }
    return;
}

# Returns the base64 form of a byte string, without line breaks.
sub base64 {
    my ($bytes) = @_;
    my @alphabet = ('A' .. 'Z', 'a' .. 'z', '0' .. '9', '+', '/');
    my $encoded = '';
    for (my $offset = 0; $offset < length $bytes; $offset += 3) {
        my $chunk = substr $bytes, $offset, 3;
        my $count = length $chunk;
        my $bits = unpack 'N', "\0" . $chunk . ("\0" x (3 - $count));
        my $text = join '', map { $alphabet[ ($bits >> $_) & 63 ] } 18, 12, 6, 0;
        substr($text, $count + 1) = '=' x (3 - $count) if $count < 3;
        $encoded .= $text;
    }
    return $encoded;
}

# Returns the base64 form of the OPC Binary type dictionary that lists every
# structure with its fields in the order of the definitions. An array field
# follows a length field of its own.
sub dictionary {
    my $text = '<?xml version="1.0" encoding="utf-8"?>'
        . '<opc:TypeDictionary DefaultByteOrder="LittleEndian" '
        . "TargetNamespace=\"$SIMATIC_URI\" "
        . 'xmlns:opc="http://opcfoundation.org/BinarySchema/" '
        . 'xmlns:ua="http://opcfoundation.org/UA/" '
        . "xmlns:tns=\"$SIMATIC_URI\">"
        . '<opc:Import Namespace="http://opcfoundation.org/UA/" '
        . 'Location="Opc.Ua.BinarySchema.bsd" />';
    for my $type (@structure_order) {
        $text .= '<opc:StructuredType BaseType="ua:ExtensionObject" Name="' . q_xml($type) . '">';
        for my $field (@{ $structures{$type}{fields} }) {
            my ($m_name, $m_type, $m_count) = tag_fields($field, "structure $type");
            data_type($m_type);
            my $type_ref = is_structure($m_type)
                ? 'tns:' . q_xml($m_type)
                : 'opc:' . $types{$m_type}{builtin};
            my $name = q_xml($m_name);
            if ($m_count) {
                $text .= "<opc:Field TypeName=\"opc:Int32\" Name=\"${name}_Size\" />";
                $text .= "<opc:Field TypeName=\"$type_ref\" Name=\"$name\" "
                    . "LengthField=\"${name}_Size\" />";
            }
            else {
                $text .= "<opc:Field TypeName=\"$type_ref\" Name=\"$name\" />";
            }
        }
        $text .= '</opc:StructuredType>';
    }
    $text .= '</opc:TypeDictionary>';
    utf8::encode($text);
    return base64($text);
}

# Writes the InputArguments or OutputArguments property of a method.
sub arguments {
    my ($node, $name, $parent, $args, $where) = @_;
    push @out, sprintf "  <UAVariable NodeId=\"%s\" BrowseName=\"%s\" ParentNodeId=\"%s\" "
        . "DataType=\"i=296\" ValueRank=\"1\" ArrayDimensions=\"%d\">\n"
        . "    <DisplayName>%s</DisplayName>\n"
        . "    <References>\n"
        . "      <Reference ReferenceType=\"HasTypeDefinition\">i=68</Reference>\n"
        . "      <Reference ReferenceType=\"HasProperty\" IsForward=\"false\">%s</Reference>\n"
        . "    </References>\n    <Value>\n      <uax:ListOfExtensionObject>\n",
        q_xml($node), $name, q_xml($parent), scalar @{$args}, $name, q_xml($parent);
    for my $arg (@{$args}) {
        my ($a_name, $a_type, $a_count) = tag_fields($arg, $where);
        exists $types{$a_type} && exists $BUILTIN_ID{ $types{$a_type}{builtin} }
            or die "$where: argument \"$a_name\" has no built-in data type\n";
        my $dims = $a_count
            ? "<uax:ArrayDimensions><uax:UInt32>$a_count</uax:UInt32></uax:ArrayDimensions>"
            : '<uax:ArrayDimensions/>';
        push @out, sprintf "        <uax:ExtensionObject>\n"
            . "          <uax:TypeId><uax:Identifier>i=297</uax:Identifier></uax:TypeId>\n"
            . "          <uax:Body>\n            <uax:Argument>\n"
            . "              <uax:Name>%s</uax:Name>\n"
            . "              <uax:DataType><uax:Identifier>i=%d</uax:Identifier></uax:DataType>\n"
            . "              <uax:ValueRank>%d</uax:ValueRank>\n              %s\n"
            . "            </uax:Argument>\n          </uax:Body>\n        </uax:ExtensionObject>\n",
            q_xml($a_name), $BUILTIN_ID{ $types{$a_type}{builtin} }, $a_count ? 1 : -1, $dims;
    }
    push @out, "      </uax:ListOfExtensionObject>\n    </Value>\n  </UAVariable>\n";
    return;
}

# Writes one data block: its Object below the area folder, its tags, its
# method with the argument properties, and its interface folders.
sub block {
    my ($db) = @_;
    ref $db eq 'HASH' or die "a block is not an object\n";
    for my $key (qw(name area comment)) {
        defined $db->{$key} && !ref $db->{$key} or die "a block has no $key\n";
    }
    my $where = "block $db->{name}";
    my $node = $NS . 's="' . $db->{name} . '"';
    my $area = $NS . 's=' . $db->{area};
    push @out, "\n  <!-- $db->{comment} -->\n";

    my $typedef = 'i=58';
    if (defined $db->{functionBlock}) {
        my $fb = $db->{functionBlock};
        $typedef = $NS . 's=OT_"' . $fb . '"';
        if (!$block_types_written{$fb}++) {
            push @out, sprintf "  <UAObjectType NodeId=\"%s\" BrowseName=\"1:%s\">\n"
                . "    <DisplayName>%s</DisplayName>\n    <References>\n"
                . "      <Reference ReferenceType=\"HasSubtype\" IsForward=\"false\">%si=%d</Reference>\n"
                . "    </References>\n  </UAObjectType>\n",
                q_xml($typedef), q_xml($fb), q_xml($fb), $NS, $ID_BLOCK_TYPE;
        }
    }
    object($node, '1:' . $db->{name}, $area, $typedef, 'Organizes');

    for my $t (@{ list_of($db->{tags}, "$where: tags") }) {
        my ($name, $type, $count, $start, $access) = tag_fields($t, $where);
        my $member = $db->{flat} ? "$node.$name" : "$node.\"$name\"";
        tag($member, $name, $node, 'HasComponent', $type, $count, $start, $access);
    }

    if (defined $db->{method}) {
        ref $db->{method} eq 'HASH' or die "$where: method is not an object\n";
        my $method = $node . '.Method';
        push @out, sprintf "  <UAMethod NodeId=\"%s\" BrowseName=\"1:Method\" ParentNodeId=\"%s\">\n"
            . "    <DisplayName>Method</DisplayName>\n    <References>\n"
            . "      <Reference ReferenceType=\"HasComponent\" IsForward=\"false\">%s</Reference>\n"
            . "    </References>\n  </UAMethod>\n",
            q_xml($method), q_xml($node), q_xml($node);
        my $in  = list_of($db->{method}{in},  "$where: method in");
        my $out = list_of($db->{method}{out}, "$where: method out");
        arguments($method . '.InputArguments', 'InputArguments', $method, $in, $where)
            if @{$in};
        arguments($method . '.OutputArguments', 'OutputArguments', $method, $out, $where)
            if @{$out};
    }

    for my $entry (@BLOCK_FOLDERS) {
        my ($folder, $number) = @{$entry};
        next if !exists $db->{$folder};
        my $f_node = $node . '.' . $folder;
        my $ref = $NS . 'i=' . $number;
        object($f_node, '1:' . $folder, $node, 'i=61', $ref);
        for my $t (@{ list_of($db->{$folder}, "$where: $folder") }) {
            my ($name, $type, $count, $start, $access) = tag_fields($t, $where);
            tag("$node.\"$name\"", $name, $f_node, $ref, $type, $count, $start, $access);
        }
    }
    return;
}

# Returns a list of the description, or an empty list for a missing one.
sub list_of {
    my ($value, $where) = @_;
    return [] if !defined $value;
    ref $value eq 'ARRAY' or die "$where is not a list\n";
    return $value;
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

    ref $doc->{types} eq 'HASH' or die "$path: \"types\" is not an object\n";
    for my $name (sort keys %{ $doc->{types} }) {
        my $type = $doc->{types}{$name};
        ref $type eq 'HASH' && defined $type->{alias} && defined $type->{builtin}
            or die "$path: type \"$name\" needs alias and builtin\n";
    }
    %types = %{ $doc->{types} };

    for my $spec (@{ list_of($doc->{structures}, "$path: \"structures\"") }) {
        ref $spec eq 'HASH' && defined $spec->{name} && ref $spec->{fields} eq 'ARRAY'
            or die "$path: a structure needs name and fields\n";
        !exists $structures{ $spec->{name} }
            or die "$path: structure $spec->{name} is defined twice\n";
        $spec->{variableType} = 1 if !exists $spec->{variableType};
        $structures{ $spec->{name} } = $spec;
        push @structure_order, $spec->{name};
    }

    ref $doc->{sections} eq 'ARRAY' && @{ $doc->{sections} }
        or die "$path: \"sections\" is not a list\n";
    list_of($doc->{blocks}, "$path: \"blocks\"");
    list_of($doc->{memory}, "$path: \"memory\"");
    return $doc;
}

# Builds the NodeSet text from the sections of the description, in order: a
# file name inserts that file, "@structures", "@blocks", and "@memory" insert
# the generated nodes.
sub build {
    my ($doc, $base) = @_;
    my @parts;
    for my $section (@{ $doc->{sections} }) {
        @out = ();
        if ($section eq '@structures') {
            structure_types();
        }
        elsif ($section eq '@blocks') {
            block($_) for @{ list_of($doc->{blocks}, 'blocks') };
        }
        elsif ($section eq '@memory') {
            push @out, "\n  <!-- Memory tags: the NodeId is the tag name in quotation marks -->\n";
            for my $t (@{ list_of($doc->{memory}, 'memory') }) {
                my ($name, $type, $count, $start, $access) = tag_fields($t, 'memory');
                tag($NS . 's="' . $name . '"', $name, $NS . 's=' . $MEMORY_AREA, 'Organizes',
                    $type, $count, $start, $access);
            }
        }
        else {
            my $file = File::Spec->file_name_is_absolute($section)
                ? $section
                : File::Spec->catfile($base, $section);
            my $text = read_file($file);
            my $encoded = dictionary();
            $text =~ s/\Q$DICTIONARY_PLACEHOLDER\E/$encoded/g;
            push @parts, $text;
            next;
        }
        my $text = join '', @out;
        utf8::encode($text);
        push @parts, $text;
    }
    return join('', @parts) . "</UANodeSet>\n";
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
    my $text = build($doc, dirname($args[0]));
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
    print STDERR "simatic-nodeset: $error";
    $status = $EXIT_ERROR;
};
exit $status;

__END__

=head1 NAME

simatic-nodeset.pl - write the NodeSet2 XML file of a SIMATIC server interface

=head1 SYNOPSIS

simatic-nodeset.pl [--output <file>] <description.json>

simatic-nodeset.pl --help

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

=item C<sections>

List of the parts of the NodeSet in output order. A file name, relative to
the directory of the description, inserts that XML file; C<@TYPE_DICTIONARY@>
in it is replaced by the binary type dictionary of all structures.
C<@structures>, C<@blocks>, and C<@memory> insert the generated nodes. The
closing C<UANodeSet> tag is added at the end.

=item C<types>

Object that maps each SIMATIC data type name to C<alias>, the DataType alias
in the NodeSet, and C<builtin>, the OPC UA built-in type that carries the
value. C<length> makes every tag of the type an array of that length.

=item C<structures>

List of structures in definition order. C<name> is the text that follows
C<DT_> in the NodeId, quotation marks included. C<fields> is a list of tags.
C<browseName> sets a browse name other than the name. C<existing> marks a
structure whose type nodes a section file holds. C<system> places the type
below SimaticSystemStructures. C<variableType> set to false leaves out the
VariableType. C<memberAccess> sets the access level of the member Variables.

=item C<blocks>

List of data blocks. C<name>, C<area> (the area folder), and C<comment> are
required. C<functionBlock> names the function block of an instance data
block. C<flat> writes member NodeIds without quotation marks. C<tags> is a
list of tags. C<method> holds the lists C<in> and C<out> of arguments.
C<Inputs>, C<Outputs>, C<InOuts>, and C<Static> are lists of the tags in
that folder.

=item C<memory>

List of memory tags.

=back

A tag is an object with C<name> and C<type>, and optionally C<length> for an
array, C<start> for the start value, and C<access> for the access level (1
read, 3 read and write, the default). The start value of an array is a list,
of a structure an object that maps member names to values.

=head1 EXIT STATUS

0 when the NodeSet was written, 1 on an error in the description or in file
access, 2 on a usage error.

=cut
