#!/usr/bin/env perl
#
# Proves that the tests can fail. For each row of a fault table the tool makes a
# scratch copy of the tree, applies the fault to one file, runs "make test" in
# the copy, and compares the failed checks with the checks the row expects.
# See the POD at the end of the file.

use strict;
use warnings;

use Cwd qw(abs_path);
use Digest::SHA qw(sha256_hex);
use File::Basename qw(dirname);
use File::Spec;
use Getopt::Long qw(GetOptionsFromArray);
use JSON::PP;
use POSIX ();
use Pod::Usage qw(pod2usage);

my $EXIT_OK    = 0;
my $EXIT_FAIL  = 1;
my $EXIT_USAGE = 2;

# Compiler flags of the copies: the shipped flags without -Werror, because a
# fault may leave an unused value behind.
my $CFLAGS = '-std=c99 -O2 -g -Wall -Wextra';

# Seconds one "make test" run may take.
my $RUN_SECONDS = 900;

# Variables given to "make test" with --make-var, as NAME=VALUE.
my @MAKE_VARS;

# Number of checks of the control run; a copy that runs fewer died on the way.
my $EXPECTED;

sub read_file {
    my ($path) = @_;
    open(my $fh, '<:raw', $path) or die "$path: $!\n";
    local $/;
    my $data = <$fh>;
    close($fh) or die "$path: $!\n";
    return $data;
}

sub write_file {
    my ($path, $data) = @_;
    open(my $fh, '>:raw', $path) or die "$path: $!\n";
    print {$fh} $data or die "$path: $!\n";
    close($fh) or die "$path: $!\n";
    return;
}

# Runs a command without a shell, sends its output to a file, and returns the
# exit status, or "signal <n>". A command that runs longer than the limit is
# stopped with SIGKILL and reports "timeout".
sub run_logged {
    my ($dir, $log, $seconds, @command) = @_;
    my $pid = fork();
    defined $pid or die "fork: $!\n";
    if (!$pid) {
        chdir $dir or POSIX::_exit(126);
        open(STDOUT, '>', $log) or POSIX::_exit(126);
        open(STDERR, '>&', \*STDOUT) or POSIX::_exit(126);
        { exec { $command[0] } @command; }
        POSIX::_exit(127);
    }
    my $deadline = time + $seconds;
    my $done = 0;
    while (!$done) {
        my $got = waitpid($pid, POSIX::WNOHANG());
        if ($got == $pid) {
            $done = 1;
        }
        elsif (time >= $deadline) {
            kill 'KILL', $pid;
            waitpid($pid, 0);
            return 'timeout';
        }
        else {
            select(undef, undef, undef, 0.5);
        }
    }
    return ($? & 127) ? 'signal ' . ($? & 127) : $? >> 8;
}

# Returns true when $path lies strictly below $base.
sub inside {
    my ($base, $path) = @_;
    my $b = abs_path($base);
    my $p = abs_path($path);
    return defined $b && defined $p && $p ne $b && index($p, "$b/") == 0;
}

# Loads and checks a fault table.
sub load_table {
    my ($path) = @_;
    my $doc = eval { JSON::PP->new->utf8->decode(read_file($path)) };
    defined $doc or die "$path: not valid JSON: $@";
    ref $doc eq 'HASH' && ref $doc->{mutations} eq 'ARRAY' or die "$path: no list \"mutations\"\n";
    my %seen;
    for my $row (@{ $doc->{mutations} }) {
        ref $row eq 'HASH' or die "$path: a row is not an object\n";
        for my $key (qw(id file old new)) {
            defined $row->{$key} && !ref $row->{$key} or die "$path: a row lacks \"$key\"\n";
        }
        ref $row->{intended} eq 'ARRAY' && @{ $row->{intended} } or die "$path: $row->{id}: no \"intended\" list\n";
        $row->{also} //= [];
        ref $row->{also} eq 'ARRAY' or die "$path: $row->{id}: \"also\" is not a list\n";
        $row->{id} =~ /\A[A-Za-z0-9][A-Za-z0-9._-]*\z/ or die "$path: $row->{id}: an id is one plain name\n";
        $seen{ $row->{id} }++ and die "$path: the id $row->{id} occurs twice\n";
    }
    return @{ $doc->{mutations} };
}

# Copies the tree to $dest/src and returns the path of the copy.
sub copy_tree {
    my ($tree, $dest) = @_;
    mkdir $dest or die "$dest: $!\n";
    my $status = system { 'cp' } 'cp', '-a', '--', $tree, File::Spec->catdir($dest, 'src');
    $status == 0 or die "cannot copy $tree to $dest\n";
    return File::Spec->catdir($dest, 'src');
}

# Applies a row to a fresh copy. Dies when the old text does not occur exactly
# once or the copy would equal the tree.
sub build_copy {
    my ($tree, $work, $row) = @_;
    $row->{file} !~ m{\A/} && $row->{file} !~ m{(\A|/)\.\.(/|\z)} or die "$row->{id}: the file must lie inside the tree\n";
    my $source = File::Spec->catfile($tree, $row->{file});
    -f $source && !-l $source or die "$row->{id}: $row->{file} is not a plain file of the tree\n";
    my $text = read_file($source);
    my $count = 0;
    my $at = 0;
    while (($at = index($text, $row->{old}, $at)) >= 0) {
        $count++;
        $at += length $row->{old};
    }
    $count == 1 or die "$row->{id}: the old text occurs $count times in $row->{file}\n";
    my $changed = $text;
    substr($changed, index($text, $row->{old}), length $row->{old}) = $row->{new};
    $changed ne $text or die "$row->{id}: the copy does not differ from the tree\n";
    my $dest = File::Spec->catdir($work, $row->{id});
    my $copy = copy_tree($tree, $dest);
    my $target = File::Spec->catfile($copy, $row->{file});
    write_file($target, $changed);
    return ($copy, sha256_hex($text), sha256_hex($changed));
}

# Runs "make test" in a copy and returns the verdict facts: whether the run is
# complete, the failed check names, and the exit status.
sub run_copy {
    my ($copy, $log) = @_;
    my $status = run_logged($copy, $log, $RUN_SECONDS, 'make', 'test', "CFLAGS=$CFLAGS", @MAKE_VARS);
    my $text = -f $log ? read_file($log) : '';
    my @failed = $text =~ /^#\s+Failed test '(.*)'$/mg;
    my $summary = $text =~ /^Files=\d+, Tests=(\d+)/m ? $1 : undef;
    my $broken = $text =~ /Parse errors|Bailout|No plan found|skipped:/;
    $broken ||= defined $EXPECTED && defined $summary && $summary != $EXPECTED;
    my $complete = defined $summary && !$broken
        && (($status eq '0' && !@failed) || ($status ne '0' && @failed));
    return ($complete, \@failed, $status, $summary);
}

sub expected_failure {
    my ($row, $name) = @_;
    return 1 if grep { $_ eq $name } @{ $row->{intended} };
    return 1 if grep { index($name, $_) >= 0 } @{ $row->{also} };
    return 0;
}

# Runs one row and returns its result record.
sub run_row {
    my ($tree, $work, $row) = @_;
    my %result = (id => $row->{id});
    my ($copy, $original, $mutated) = eval { build_copy($tree, $work, $row) };
    if (!defined $copy) {
        my $error = $@;
        chomp $error;
        @result{qw(verdict detail)} = ('NOT-BUILT', $error);
        return \%result;
    }
    my $log = File::Spec->catfile($work, $row->{id}, 'run.log');
    my ($complete, $failed, $status, $summary) = run_copy($copy, $log);
    my $actual = sha256_hex(read_file(File::Spec->catfile($copy, $row->{file})));
    my @missed = grep { my $i = $_; !grep { $_ eq $i } @{$failed} } @{ $row->{intended} };
    my @unexpected = grep { !expected_failure($row, $_) } @{$failed};
    $result{failed} = scalar @{$failed};
    if ($actual ne $mutated) {
        $result{verdict} = 'HASH-MISMATCH';
    }
    elsif (!$complete) {
        $result{verdict} = 'INCOMPLETE';
        $result{detail} = "make test status $status; see $log";
    }
    elsif (!@missed && !@unexpected) {
        $result{verdict} = 'KILLED';
    }
    elsif (!@{$failed}) {
        $result{verdict} = defined $row->{equivalent} ? 'EQUIVALENT' : 'SURVIVED';
        $result{detail} = $row->{equivalent} if defined $row->{equivalent};
    }
    else {
        $result{verdict} = 'CHECK';
        $result{detail} = join('; ', (@missed ? 'not failed: ' . join(', ', @missed) : ()),
            (@unexpected ? 'unexpected: ' . join(', ', @unexpected) : ()));
    }
    return \%result;
}

sub main {
    my @args = @_;
    my ($tree, $table, $work, $jobs, $help) = (undef, undef, undef, 3, 0);
    GetOptionsFromArray(\@args, 'tree=s' => \$tree, 'table=s' => \$table, 'work=s' => \$work,
        'jobs=i' => \$jobs, 'make-var=s' => \@MAKE_VARS, 'help|h' => \$help) or return $EXIT_USAGE;
    if ($help) {
        pod2usage(-exitval => 'NOEXIT', -verbose => 1, -output => \*STDOUT);
        return $EXIT_OK;
    }
    if (!defined $tree || !defined $table || !defined $work || $jobs < 1) {
        pod2usage(-exitval => 'NOEXIT', -verbose => 0, -output => \*STDERR);
        return $EXIT_USAGE;
    }
    -d $tree or die "$tree: not a directory\n";
    $tree = abs_path($tree);
    mkdir $work or die "$work: $!\n" if !-d $work;
    $work = abs_path($work);
    !inside($tree, $work) && $work ne $tree or die "the work directory lies inside the tree\n";
    my @rows = load_table($table);
    my %known = map { $_->{id} => 1 } @rows;
    for my $id (@args) {
        $known{$id} or die "unknown id $id\n";
    }
    @rows = grep { my $r = $_; !@args || grep { $_ eq $r->{id} } @args } @rows;

    # The unchanged tree runs first, through the same entry point.
    my $control = File::Spec->catdir($work, 'control');
    -e $control and die "$control exists; use an empty work directory\n";
    my $copy = copy_tree($tree, $control);
    my $control_log = File::Spec->catfile($control, 'run.log');
    my ($complete, $failed, $status, $summary) = run_copy($copy, $control_log);
    if (@{$failed}) {
        print STDERR "control run: the unchanged tree fails " . scalar(@{$failed}) . " check(s): "
            . join('; ', @{$failed}) . "\nsee $control_log; no series run\n";
        return $EXIT_FAIL;
    }
    if (!$complete || $status ne '0') {
        print STDERR "control run: the unchanged tree did not run every check (a test was skipped or stopped; "
            . "make test status $status); see $control_log; no series run\n"
            . "a skipped server test usually needs --make-var UA_NODESET_PATH=<absolute path of the UA-Nodeset directory>\n";
        return $EXIT_FAIL;
    }
    print "control: passed all $summary checks\n";
    $EXPECTED = $summary;

    my %result;
    my %running;
    my @queue = @rows;
    while (@queue || %running) {
        while (@queue && keys %running < $jobs) {
            my $row = shift @queue;
            pipe(my $reader, my $writer) or die "pipe: $!\n";
            my $pid = fork();
            defined $pid or die "fork: $!\n";
            if (!$pid) {
                close($reader);
                my $record = eval { run_row($tree, $work, $row) }
                    || { id => $row->{id}, verdict => 'NOT-BUILT', detail => "$@" };
                print {$writer} JSON::PP->new->canonical->encode($record);
                close($writer);
                POSIX::_exit(0);
            }
            close($writer);
            $running{$pid} = [$row->{id}, $reader];
        }
        my $done = wait();
        next if $done < 0 || !$running{$done};
        my ($id, $reader) = @{ delete $running{$done} };
        my $json = do { local $/; <$reader> };
        close($reader);
        my $record = eval { JSON::PP->new->decode($json // '') };
        $result{$id} = $record || { id => $id, verdict => 'INCOMPLETE', detail => 'no result from the row process' };
        printf "%-34s %s%s\n", $id, $result{$id}{verdict}, defined $result{$id}{detail} ? " ($result{$id}{detail})" : '';
    }

    my %count;
    $count{ $_->{verdict} }++ for values %result;
    print join(', ', map { "$_ $count{$_}" } sort keys %count), "\n";
    my $bad = grep { $_ ne 'KILLED' && $_ ne 'EQUIVALENT' } keys %count;
    return $bad ? $EXIT_FAIL : $EXIT_OK;
}

my $status;
eval {
    $status = main(@ARGV);
    defined $status or die "internal error: main returned no exit status\n";
    1;
} or do {
    my $error = $@;
    print STDERR "mutation-check: $error";
    $status = $EXIT_FAIL;
};
exit $status;

__END__

=head1 NAME

mutation-check.pl - show that the tests of the tree can fail

=head1 SYNOPSIS

mutation-check.pl --tree DIR --table FILE --work DIR [--jobs N] [--make-var NAME=VALUE ...] [ID ...]

=head1 DESCRIPTION

The fault table is a JSON object with a list C<mutations>. A row has C<id>,
C<file> (relative to the tree), C<old> (text that occurs exactly once in the
file), C<new>, C<intended> (names of the checks the fault must fail), and
optionally C<also> (text of the names of other checks it may fail) and
C<equivalent> (the reason the fault changes no observable).

The tool first copies the unchanged tree to C<WORK/control> and runs
C<make test> in the copy; the series starts only when every check passes. Each
row then gets its own copy, with the fault applied to the named file and the
SHA-256 of that file recorded before and after, and runs C<make test> in it.
C<make test> runs with the shipped compiler flags without C<-Werror>.

A row is C<KILLED> when every intended check failed and no check failed
outside C<intended> and C<also>, C<SURVIVED> when no check failed,
C<EQUIVALENT> when a row with C<equivalent> survived, C<CHECK> when the failed
checks differ from the expectation, and C<INCOMPLETE> when the run did not
finish or ended without a verdict of its own (run it again alone). C<WORK> must
be outside the tree and is never removed by the tool.

=head1 OPTIONS

=over 4

=item B<--tree> DIR

The tree to copy; the root of the repository.

=item B<--table> FILE

The fault table.

=item B<--work> DIR

Where the copies and run logs go. C<DIR/control> must not exist.

=item B<--jobs> N

Runs at the same time; the default is 3.

=item B<--make-var> NAME=VALUE

A variable for C<make test> in every copy, for a path that is relative to the
tree and breaks in a copy, such as C<UA_NODESET_PATH>. May be repeated.

=item B<--help>

Prints this text.

=back

=head1 EXIT STATUS

0 when every row is C<KILLED> or C<EQUIVALENT>, 1 for any other row or a
failed control run or an error, 2 for a usage error.

=cut
