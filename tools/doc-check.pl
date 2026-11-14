#!/usr/bin/env perl
#
# Runs the commands that the pages of the book show and compares what they print
# with what the pages state. Every page runs in its own clean checkout of the
# tree. The tool prints TAP with one check per command block. See the POD at the
# end of the file.

use strict;
use warnings;

use Cwd qw(abs_path);
use File::Basename qw(dirname);
use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use Getopt::Long qw(GetOptionsFromArray);
use IO::Select;
use POSIX ();
use Pod::Usage qw(pod2usage);

my $EXIT_OK    = 0;
my $EXIT_FAIL  = 1;
my $EXIT_USAGE = 2;

# Directory of the pages relative to the tree, and the page that only lists the
# other pages.
my $SOURCE_DIRECTORY = File::Spec->catdir('docs', 'src');
my $SUMMARY_PAGE     = 'SUMMARY.md';

# Prefix of the environment variables that carry the values of the placeholders:
# DOC_CHECK_VALUE_<name> gives the value of <name>.
my $VALUE_PREFIX = 'DOC_CHECK_VALUE_';

# Seconds a command may run, and seconds a background command may take to print
# its ready text. The sleep between two reads is in fractions of a second.
my $COMMAND_SECONDS = 600;
my $READY_SECONDS   = 120;
my $POLL_SECONDS    = 0.2;

# Seconds between the signal that stops a command and the signal that kills it.
my $STOP_GRACE_SECONDS = 20;

# Placeholder of a value that the reader replaces, and the built-in name that the
# tool replaces with the path of the clean checkout of the page.
my $PLACEHOLDER = qr/<([a-z][a-z0-9_]*)>/;
my $CHECKOUT_NAME = 'checkout';

# Marks in a page: an HTML comment before a command block.
my $MARK = qr/^\s*<!--\s*doc-check:\s*(.*?)\s*-->\s*$/;

# Number of characters of a command in the name of its check.
my $NAME_LENGTH = 60;

my @BACKGROUND;
my $CHECK_COUNT = 0;
my $FAILED      = 0;

END {
    stop_background();
}

sub read_file {
    my ($path) = @_;
    open(my $fh, '<:raw', $path) or die "$path: $!\n";
    local $/;
    my $data = <$fh>;
    close($fh) or die "$path: $!\n";
    return $data;
}

# Prints one TAP check. A failed check also prints the lines that the Test::More
# diagnostics have, on standard error as Test::More does, so that prove shows
# them and tools that read those lines work with this output.
sub report {
    my ($ok, $name, $directive, @diagnostics) = @_;
    $CHECK_COUNT++;
    $name =~ s/[\r\n]+/ /g;
    if ($ok) {
        print "ok $CHECK_COUNT - $name" . (defined $directive ? " # $directive" : '') . "\n";
        return;
    }
    $FAILED++;
    print "not ok $CHECK_COUNT - $name\n";
    STDOUT->flush();
    print STDERR "#   Failed test '$name'\n";
    for my $line (map { split /\n/, $_, -1 } @diagnostics) {
        print STDERR "#   $line\n";
    }
    return;
}

# Lists the files of the tree that Git does not ignore, tracked or not.
sub list_files {
    my ($tree) = @_;
    my $pid = open(my $out, '-|');
    defined $pid or die "git: fork: $!\n";
    if (!$pid) {
        chdir $tree or POSIX::_exit(126);
        { no warnings 'exec'; exec { 'git' } 'git', 'ls-files', '-z', '--cached', '--others', '--exclude-standard'; }
        POSIX::_exit(127);
    }
    my $text = do { local $/; <$out> };
    close($out);
    $? == 0 or die "git ls-files failed in $tree\n";
    return grep { length } split /\0/, defined $text ? $text : '';
}

# Makes a clean checkout of the listed files, with their modes, and returns its
# path.
sub make_checkout {
    my ($tree, $files, $parent) = @_;
    my $checkout = tempdir('page-XXXXXX', DIR => $parent, CLEANUP => 0);
    for my $file (@{$files}) {
        my $from = File::Spec->catfile($tree, $file);
        next if !-f $from;
        my $to = File::Spec->catfile($checkout, $file);
        make_path(dirname($to));
        copy($from, $to) or die "copy $from: $!\n";
        chmod((stat $from)[2] & 07777, $to) or die "chmod $to: $!\n";
    }
    return $checkout;
}

# Finds the command blocks of a page. A block is a code fence with the language
# bash; the first code fence without a language after it, before the next
# heading or the next bash fence, is the output that the page states. A mark in
# a comment before the fence sets the mode of the block.
sub parse_page {
    my ($text) = @_;
    my @blocks;
    my ($mark, $block_mark, $open, $indent, @body);
    my $last;
    for my $line (split /\n/, $text, -1) {
        if (defined $open) {
            if ($line =~ /^\s*```\s*$/) {
                if ($open eq 'bash') {
                    $last = { command => [@body], mark => $block_mark, output => undef };
                    push @blocks, $last;
                }
                elsif ($open eq '' && defined $last && !defined $last->{output}) {
                    $last->{output} = join("\n", @body);
                }
                $open = undef;
                @body = ();
            }
            else {
                (my $content = $line) =~ s/^ {0,$indent}//;
                push @body, $content;
            }
            next;
        }
        if ($line =~ /^(\s*)```(\S*)\s*$/) {
            $indent = length $1;
            $open = $2;
            @body = ();
            $block_mark = $open eq 'bash' ? $mark : undef;
            $mark = undef;
            next;
        }
        if ($line =~ $MARK) {
            $mark = $1;
            next;
        }
        if ($line =~ /^#/) {
            $last = undef;
            $mark = undef;
        }
    }
    return @blocks;
}

# Replaces every placeholder with its value. Returns the text, the names that
# have no value, and the names whose value is empty, which stands for a
# prerequisite that was not given.
sub replace_placeholders {
    my ($text, $values) = @_;
    my (@missing, @empty);
    $text =~ s{$PLACEHOLDER}{
        !defined $values->{$1} ? do { push @missing, $1; "<$1>" }
            : !length $values->{$1} ? do { push @empty, $1; "<$1>" }
            : $values->{$1}
    }ge;
    return ($text, \@missing, \@empty);
}

# Removes the text that differs between two runs of the same command: escape
# sequences, timestamps, hashes, elapsed and CPU times, process ids, ports,
# modification times, and the path of the clean checkout. Both sides of a
# comparison pass through it.
sub normalize {
    my ($text, $checkout) = @_;
    $text =~ s/\x1b\[[0-9;]*[A-Za-z]//g;
    $text =~ s/\Q$checkout\E/<checkout>/g if defined $checkout && length $checkout;
    $text =~ s/\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(?:\.\d+)?(?: \(UTC[+-]\d+\))?Z?/<timestamp>/g;
    $text =~ s/\b[0-9a-f]{40,64}\b/<hash>/g;
    $text =~ s/\d+ wallclock secs \([^)]*\)/<elapsed>/g;
    $text =~ s/\b(pid|PID)[= ]\d+/$1=<pid>/g;
    $text =~ s{(://[^/:\s]+):\d+}{$1:<port>}g;
    $text =~ s/\b(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) +\d+ +\d{2}:\d{2}\b/<mtime>/g;
    $text =~ s/[ \t]+$//mg;
    $text =~ s/\n+\z//;
    return $text;
}

sub child_environment {
    my @names = grep { index($_, $VALUE_PREFIX) != 0 } keys %ENV;
    return map { $_ => $ENV{$_} } @names;
}

# Starts a command in its own process group with its output in a file, and
# returns the process id.
sub start_command {
    my ($checkout, $line, $output) = @_;
    my $pid = fork();
    defined $pid or die "fork: $!\n";
    if (!$pid) {
        POSIX::setpgid(0, 0);
        # A shell that starts this tool in the background leaves INT ignored, and
        # an ignored INT cannot be trapped; the command needs the default action.
        $SIG{INT} = 'DEFAULT';
        %ENV = child_environment();
        chdir $checkout or POSIX::_exit(126);
        open(STDIN, '<', File::Spec->devnull) or POSIX::_exit(126);
        open(STDOUT, '>', $output) or POSIX::_exit(126);
        open(STDERR, '>&', \*STDOUT) or POSIX::_exit(126);
        { no warnings 'exec'; exec { 'bash' } 'bash', '-c', $line; }
        POSIX::_exit(127);
    }
    return $pid;
}

# Waits for a process until the deadline. Returns true and sets $? when it ended.
sub wait_until {
    my ($pid, $seconds) = @_;
    my $deadline = time + $seconds;
    while (1) {
        my $done = waitpid($pid, POSIX::WNOHANG());
        return 1 if $done == $pid || $done == -1;
        return 0 if time >= $deadline;
        select(undef, undef, undef, $POLL_SECONDS);
    }
}

# Stops the group of a process: INT first, then TERM, then KILL.
sub stop_group {
    my ($pid) = @_;
    for my $signal ('INT', 'TERM', 'KILL') {
        kill($signal, -$pid);
        return if wait_until($pid, $STOP_GRACE_SECONDS);
    }
    return;
}

sub stop_background {
    for my $entry (splice @BACKGROUND) {
        stop_group($entry->{pid}) if kill(0, $entry->{pid});
    }
    return;
}

# Runs a command to its end and returns the exit status, or the signal as a text
# when it was killed, and its output.
sub run_command {
    my ($checkout, $line, $seconds) = @_;
    my $output = File::Spec->catfile($checkout, '.doc-check-output');
    my $pid = start_command($checkout, $line, $output);
    my $ended = wait_until($pid, $seconds);
    my $status;
    if ($ended) {
        $status = ($? & 127) ? 'signal ' . ($? & 127) : $? >> 8;
    }
    else {
        stop_group($pid);
        $status = "timeout after $seconds seconds";
    }
    my $text = -f $output ? read_file($output) : '';
    unlink $output;
    return ($status, $text);
}

# Starts a command that does not end by itself and waits until its output holds
# the ready text. Returns the process, the output file, and whether the text
# appeared.
sub run_background {
    my ($checkout, $line, $ready) = @_;
    my $output = File::Spec->catfile($checkout, '.doc-check-background');
    my $pid = start_command($checkout, $line, $output);
    my $entry = { pid => $pid, output => $output };
    push @BACKGROUND, $entry;
    my $deadline = time + $READY_SECONDS;
    my $seen = 0;
    while (time < $deadline) {
        $seen = 1, last if -f $output && read_file($output) =~ /$ready/;
        last if waitpid($pid, POSIX::WNOHANG()) != 0;
        select(undef, undef, undef, $POLL_SECONDS);
    }
    return ($entry, $seen);
}

# Stops the background commands of a page and returns their statuses and output.
sub finish_background {
    my ($entry) = @_;
    my $status;
    if (kill(0, $entry->{pid})) {
        kill('INT', -$entry->{pid});
        if (wait_until($entry->{pid}, $STOP_GRACE_SECONDS)) {
            # The INT of the tool ends a command such as make by the signal.
            $status = (($? & 127) == POSIX::SIGINT()) ? 0
                : ($? & 127) ? 'signal ' . ($? & 127) : $? >> 8;
        }
        else {
            stop_group($entry->{pid});
            $status = 'did not stop on INT';
        }
    }
    else {
        $status = 'ended before it was stopped';
    }
    my $text = -f $entry->{output} ? read_file($entry->{output}) : '';
    @BACKGROUND = grep { $_ != $entry } @BACKGROUND;
    return ($status, $text);
}

# Checks one page: every command block runs in the clean checkout of the page.
sub check_page {
    my ($name, $blocks, $values, $checkout) = @_;
    my %values = (%{$values}, $CHECKOUT_NAME => $checkout);
    my $number = 0;
    my @started;
    for my $block (@{$blocks}) {
        $number++;
        my @commands = grep { length && !/^\s*#/ } @{ $block->{command} };
        my $label = "$name: block $number";
        if (@commands != 1) {
            report(0, $label, undef, 'a command block holds ' . scalar(@commands) . ' commands; it must hold one');
            next;
        }
        my $shown = substr($commands[0], 0, $NAME_LENGTH);
        $label .= ": $shown";
        my $mark = defined $block->{mark} ? $block->{mark} : '';
        if ($mark =~ /^skip\b/) {
            report(1, $label, 'SKIP shown and not run');
            next;
        }
        my ($line, $missing, $empty) = replace_placeholders($commands[0], \%values);
        my $expected;
        if (defined $block->{output}) {
            # A placeholder without a value in the output stays as text: the real
            # output holds such text when a program prints angle brackets.
            my ($text, undef, $empty_output) = replace_placeholders($block->{output}, \%values);
            $expected = $text;
            push @{$empty}, @{$empty_output};
        }
        my %seen;
        if (@{$missing}) {
            my @names = grep { !$seen{$_}++ } @{$missing};
            report(0, $label, undef, 'no value for the placeholder ' . join(', ', map { "<$_>" } @names));
            next;
        }
        if (@{$empty}) {
            my @names = grep { !$seen{$_}++ } @{$empty};
            report(1, $label, 'SKIP no value given for ' . join(', ', map { "<$_>" } @names));
            next;
        }
        if ($mark =~ /^background\s+ready=(.+)$/) {
            my $ready = $1;
            my ($entry, $seen) = run_background($checkout, $line, $ready);
            push @started, [$label, $entry, $expected, $seen, $ready];
            next;
        }
        my ($status, $text) = run_command($checkout, $line, $COMMAND_SECONDS);
        evaluate($label, $status, $text, $expected, $checkout, 0);
    }
    for my $item (@started) {
        my ($label, $entry, $expected, $seen, $ready) = @{$item};
        my ($status, $text) = finish_background($entry);
        if (!$seen) {
            report(0, $label, undef, "the ready text /$ready/ did not appear within $READY_SECONDS seconds");
            next;
        }
        evaluate($label, $status, $text, $expected, $checkout, 1);
    }
    return;
}

# Compares the exit status and the output of a command with the page. A
# background command stops on INT, so its output only has to contain the output
# that the page states.
sub evaluate {
    my ($label, $status, $text, $expected, $checkout, $contains) = @_;
    my @problems;
    push @problems, "exit status $status, expected 0" if $status ne '0';
    if (defined $expected) {
        my $want = normalize($expected, $checkout);
        my $got  = normalize($text, $checkout);
        my $matches = $contains ? index($got, $want) >= 0 : $got eq $want;
        push @problems, "output differs from the page\nexpected:\n$want\ngot:\n$got" if !$matches;
    }
    report(!@problems, $label, undef, @problems);
    return;
}

# Collects the values of the placeholders from the environment and the options.
sub collect_values {
    my ($options) = @_;
    my %values;
    for my $name (keys %ENV) {
        next if index($name, $VALUE_PREFIX) != 0;
        $values{ lc substr($name, length $VALUE_PREFIX) } = $ENV{$name};
    }
    for my $pair (@{$options}) {
        $pair =~ /^([a-z][a-z0-9_]*)=(.*)$/s or die "bad --value $pair: use name=value\n";
        $values{$1} = $2;
    }
    return \%values;
}

sub find_pages {
    my ($source) = @_;
    my @pages;
    my @queue = ($source);
    while (my $directory = shift @queue) {
        opendir(my $dh, $directory) or die "$directory: $!\n";
        for my $entry (sort grep { !/^\./ } readdir $dh) {
            my $path = File::Spec->catfile($directory, $entry);
            if (-d $path) {
                push @queue, $path;
            }
            elsif ($entry =~ /\.md\z/ && $entry ne $SUMMARY_PAGE) {
                push @pages, $path;
            }
        }
        closedir($dh);
    }
    return sort { $a cmp $b } @pages;
}

sub main {
    my @args = @_;
    my ($tree, $source, $only, $help) = (undef, $SOURCE_DIRECTORY, undef, 0);
    my @value_options;
    GetOptionsFromArray(\@args, 'tree=s' => \$tree, 'source=s' => \$source, 'page=s' => \$only,
        'value=s' => \@value_options, 'seconds=i' => \$COMMAND_SECONDS,
        'ready-seconds=i' => \$READY_SECONDS, 'help|h' => \$help)
        or return $EXIT_USAGE;
    if ($help) {
        pod2usage(-exitval => 'NOEXIT', -verbose => 1, -output => \*STDOUT);
        return $EXIT_OK;
    }
    if (@args || $COMMAND_SECONDS < 1 || $READY_SECONDS < 1) {
        pod2usage(-exitval => 'NOEXIT', -verbose => 0, -output => \*STDERR);
        return $EXIT_USAGE;
    }
    $tree = abs_path(defined $tree ? $tree : File::Spec->catdir(dirname(abs_path($0)), File::Spec->updir))
        or die "the tree does not exist\n";
    my $source_path = File::Spec->catdir($tree, $source);
    -d $source_path or die "$source_path: not a directory\n";
    my $values = collect_values(\@value_options);
    my @files = list_files($tree);
    my $parent = tempdir('doc-check-XXXXXX', TMPDIR => 1, CLEANUP => 1);
    my @pages = find_pages($source_path);
    @pages = grep { $_ eq File::Spec->catfile($source_path, $only) } @pages if defined $only;
    for my $page (@pages) {
        my @blocks = parse_page(read_file($page));
        next if !@blocks;
        my $name = File::Spec->abs2rel($page, $source_path);
        my $checkout = make_checkout($tree, \@files, $parent);
        check_page($name, \@blocks, $values, $checkout);
        stop_background();
    }
    print "1..$CHECK_COUNT\n";
    return $FAILED ? $EXIT_FAIL : $EXIT_OK;
}

my $status;
eval {
    $status = main(@ARGV);
    defined $status or die "internal error: main returned no exit status\n";
    1;
} or do {
    my $error = $@;
    print STDERR "doc-check: $error";
    $status = $EXIT_USAGE;
};
exit $status;

__END__

=head1 NAME

doc-check.pl - run the commands of the pages of the book and compare their output with the pages

=head1 SYNOPSIS

doc-check.pl [--tree DIR] [--source DIR] [--page FILE] [--value NAME=VALUE ...] [--seconds N] [--ready-seconds N]

=head1 DESCRIPTION

For every page under C<docs/src> that has a command block, the tool makes a clean
checkout of the tree from the files that Git does not ignore (C<git ls-files
--cached --others --exclude-standard>), runs the commands of the page in it, and
prints TAP with one check per command block.

A command block is a code fence with the language C<bash> and holds one command
without a prompt. The first code fence without a language after it, before the next
heading or the next C<bash> fence, is the output that the page states. A comment
before the command block sets a mark: C<E<lt>!-- doc-check: skip --E<gt>> for a
command that the page shows and the tool does not run, and
C<E<lt>!-- doc-check: background ready=REGEX --E<gt>> for a command that does not end
by itself. A background command is started, the tool waits until its output matches
REGEX, and it is stopped with INT after the other commands of the page; its output
only has to contain the output of the page.

A value that the reader replaces is a placeholder C<E<lt>nameE<gt>> with a lowercase
name. Its value comes from the environment variable C<DOC_CHECK_VALUE_name> or from
C<--value name=value>. The name C<checkout> is built in and is the path of the clean
checkout of the page. A placeholder without a value in a command fails the check of its block; in the output of a block it stays as text. A placeholder whose value is empty stands for a prerequisite that was not given: the check of its block is skipped and not failed.

Both the stated output and the real output are normalized before the comparison:
escape sequences, timestamps, hashes, elapsed and CPU times, process ids, ports,
modification times, and the path of the checkout.

=head1 OPTIONS

=over 4

=item B<--tree> DIR

The tree to check. The default is the tree that holds this tool.

=item B<--source> DIR

The directory of the pages relative to the tree. The default is C<docs/src>.

=item B<--page> FILE

Check only this page, given relative to the directory of the pages.

=item B<--value> NAME=VALUE

The value of a placeholder. Repeat for each placeholder.

=item B<--seconds> N

Seconds a command may run. The default is 600.

=item B<--ready-seconds> N

Seconds a background command may take to print its ready text. The default is 120.

=back

=head1 EXIT STATUS

0 when every check passed, 1 when a check failed, 2 on a usage error or an
internal error.

=cut
