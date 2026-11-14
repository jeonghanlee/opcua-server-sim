#!/usr/bin/env perl
#
# Tests of tools/doc-check.pl through its command line. Each case makes a small
# Git repository with one page, runs the shipped tool on it, and checks the
# exit status and the TAP that the tool prints. The pages here are fixtures of
# this test and not pages of the book.

use strict;
use warnings;

use Cwd qw(abs_path);
use File::Basename qw(dirname);
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use POSIX ();
use Test::More;

my $TOOL = abs_path(File::Spec->catfile(dirname(__FILE__), File::Spec->updir, 'tools', 'doc-check.pl'));
-f $TOOL or BAIL_OUT("$TOOL is missing");

my $dir = tempdir(CLEANUP => 1);
my $counter = 0;

sub write_file {
    my ($path, $data) = @_;
    make_path(dirname($path));
    open(my $fh, '>:raw', $path) or die "$path: $!\n";
    print {$fh} $data or die "$path: $!\n";
    close($fh) or die "$path: $!\n";
    return;
}

# Makes a Git repository with the given files (relative path => content) and
# returns its path. The repository has no commit; the tool lists the files that
# Git does not ignore.
sub make_tree {
    my ($modes, %files) = @_;
    my $tree = File::Spec->catdir($dir, 'tree' . ++$counter);
    make_path($tree);
    system { 'git' } 'git', '-C', $tree, 'init', '-q' and die "git init failed\n";
    write_file(File::Spec->catfile($tree, $_), $files{$_}) for keys %files;
    chmod($modes->{$_}, File::Spec->catfile($tree, $_)) or die "chmod $_: $!\n" for keys %{$modes};
    return $tree;
}

# Runs the tool and returns the exit status, the standard output, and the
# standard error.
sub run_tool {
    my ($ignore_int, $tree, @args) = @_;
    my $err = File::Temp->new(DIR => $dir);
    my $pid = open(my $out, '-|');
    defined $pid or die "fork: $!\n";
    if (!$pid) {
        delete @ENV{ grep { /^DOC_CHECK_/ } keys %ENV };
        $SIG{INT} = 'IGNORE' if $ignore_int;
        open(STDERR, '>&', $err) or POSIX::_exit(126);
        { no warnings 'exec'; exec { $^X } $^X, $TOOL, '--tree', $tree, @args; }
        POSIX::_exit(127);
    }
    my $stdout = do { local $/; <$out> };
    close($out);
    my $status = ($? & 127) ? 'signal ' . ($? & 127) : $? >> 8;
    seek($err, 0, 0);
    my $stderr = do { local $/; <$err> };
    return ($status, defined $stdout ? $stdout : '', defined $stderr ? $stderr : '');
}

sub page {
    my ($body) = @_;
    return "# A page\n\n$body";
}

my @cases = (
    {
        name   => 'a command whose output matches the page',
        files  => { 'docs/src/a.md' => page("Run it:\n\n```bash\necho hello\n```\n\nIt prints:\n\n```\nhello\n```\n") },
        status => 0,
        tap    => [qr/^ok 1 - a\.md: block 1: echo hello$/m, qr/^1\.\.1$/m],
    },
    {
        name   => 'a code block inside a numbered step is read',
        files  => { 'docs/src/a.md' => page("1. Run it:\n\n   ```bash\n   echo hello\n   ```\n\n   It prints:\n\n   ```\n   hello\n   ```\n") },
        status => 0,
        tap    => [qr/^ok 1 - a\.md: block 1: echo hello$/m],
    },
    {
        name   => 'a changed command is found',
        files  => { 'docs/src/a.md' => page("```bash\necho world\n```\n\n```\nhello\n```\n") },
        status => 1,
        tap    => [qr/^not ok 1 - a\.md: block 1: echo world$/m, qr/^#\s+Failed test 'a\.md: block 1: echo world'$/m,
            qr/output differs from the page/],
    },
    {
        name   => 'a changed output is found',
        files  => { 'docs/src/a.md' => page("```bash\necho hello\n```\n\n```\nhellp\n```\n") },
        status => 1,
        tap    => [qr/^not ok 1 /m, qr/^#   expected:\n#   hellp\n#   got:\n#   hello$/m],
    },
    {
        name   => 'a command that fails is found',
        files  => { 'docs/src/a.md' => page("```bash\nfalse\n```\n") },
        status => 1,
        tap    => [qr/^not ok 1 /m, qr/exit status 1, expected 0/],
    },
    {
        name   => 'a placeholder with a value is replaced',
        files  => { 'docs/src/a.md' => page("```bash\necho <greeting>\n```\n\n```\nhi there\n```\n") },
        args   => ['--value', 'greeting=hi there'],
        status => 0,
        tap    => [qr/^ok 1 /m],
    },
    {
        name   => 'a placeholder without a value is found',
        files  => { 'docs/src/a.md' => page("```bash\necho <missing_name>\n```\n") },
        status => 1,
        tap    => [qr/^not ok 1 /m, qr/no value for the placeholder <missing_name>/],
    },
    {
        name   => 'a placeholder with an empty value is skipped',
        files  => { 'docs/src/a.md' => page("```bash\necho <epics_tree>\n```\n") },
        args   => ['--value', 'epics_tree='],
        status => 0,
        tap    => [qr/^ok 1 - .*# SKIP no value given for <epics_tree>$/m],
    },
    {
        name   => 'a placeholder in the output without a value is compared as text',
        files  => { 'docs/src/a.md' => page("```bash\nprintf '\\074usage_text\\076\\n'\n```\n\n```\n<usage_text>\n```\n") },
        status => 0,
        tap    => [qr/^ok 1 /m],
    },
    {
        name   => 'a placeholder in the output that the command does not print is found',
        files  => { 'docs/src/a.md' => page("```bash\necho hello\n```\n\n```\n<missing_output>\n```\n") },
        status => 1,
        tap    => [qr/^not ok 1 /m, qr/output differs from the page/],
    },
    {
        name   => 'the volatile text of both sides is normalized',
        files  => { 'docs/src/a.md' =>
            page("```bash\ndate -u +%Y-%m-%dT%H:%M:%S\n```\n\n```\n2000-01-01T00:00:00\n```\n") },
        status => 0,
        tap    => [qr/^ok 1 /m],
    },
    {
        name   => 'the path of the checkout is the built-in placeholder',
        files  => { 'docs/src/a.md' => page("```bash\npwd\n```\n\n```\n<checkout>\n```\n") },
        status => 0,
        tap    => [qr/^ok 1 /m],
    },
    {
        name   => 'a command that is shown and not run is skipped',
        files  => { 'docs/src/a.md' => page("<!-- doc-check: skip -->\n```bash\nfalse\n```\n") },
        status => 0,
        tap    => [qr/^ok 1 - .*# SKIP shown and not run$/m],
    },
    {
        name   => 'a command block with two commands is found',
        files  => { 'docs/src/a.md' => page("```bash\necho a\necho b\n```\n") },
        status => 1,
        tap    => [qr/^not ok 1 /m, qr/holds 2 commands; it must hold one/],
    },
    {
        name   => 'a file that Git ignores is not in the clean checkout, and a new file is',
        files  => {
            '.gitignore'    => "secret.txt\n",
            'secret.txt'    => "secret\n",
            'new.txt'       => "new\n",
            'docs/src/a.md' => page("```bash\ntest ! -e secret.txt\n```\n\n```bash\ntest -e new.txt\n```\n"),
        },
        status => 0,
        tap    => [qr/^ok 1 /m, qr/^ok 2 /m],
    },
    {
        name   => 'a command that does not end by itself runs in the background',
        files  => { 'docs/src/a.md' => page(
            "<!-- doc-check: background ready=ready -->\n"
            . "```bash\nsh -c 'trap \"exit 0\" INT; echo ready; while :; do sleep 1; done'\n```\n\n```\nready\n```\n") },
        status => 0,
        tap    => [qr/^ok 1 /m],
    },
    {
        name   => 'a background command can trap INT when the tool was started with INT ignored',
        files  => { 'docs/src/a.md' => page(
            "<!-- doc-check: background ready=ready -->\n"
            . "```bash\nsh -c 'trap \"exit 0\" INT; echo ready; while :; do sleep 1; done'\n```\n\n```\nready\n```\n") },
        ignore_int => 1,
        status => 0,
        tap    => [qr/^ok 1 /m],
    },
    {
        name   => 'a background command that the INT of the tool ends by the signal is accepted',
        files  => { 'docs/src/a.md' => page(
            "<!-- doc-check: background ready=ready -->\n"
            . "```bash\nsh -c 'echo ready; while :; do sleep 1; done'\n```\n\n```\nready\n```\n") },
        status => 0,
        tap    => [qr/^ok 1 /m],
    },
    {
        name   => 'a background command that never prints its ready text is found',
        files  => { 'docs/src/a.md' => page(
            "<!-- doc-check: background ready=never-printed -->\n"
            . "```bash\nsh -c 'trap \"exit 0\" INT; echo other; sleep 3'\n```\n") },
        args   => ['--ready-seconds', '1'],
        status => 1,
        tap    => [qr/^not ok 1 /m, qr/the ready text \/never-printed\/ did not appear within 1 seconds/],
    },
    {
        name   => 'a command that runs too long is found',
        files  => { 'docs/src/a.md' => page("```bash\nsleep 30\n```\n") },
        args   => ['--seconds', '1'],
        status => 1,
        tap    => [qr/^not ok 1 /m, qr/timeout after 1 seconds/],
    },
    {
        name   => 'escape sequences are removed from both sides',
        files  => { 'docs/src/a.md' => page("```bash\nprintf '\\033[1mbold\\033[0m\\n'\n```\n\n```\nbold\n```\n") },
        status => 0,
        tap    => [qr/^ok 1 /m],
    },
    {
        name   => 'a timestamp with a letter T, a fraction, and a zone is normalized',
        files  => { 'docs/src/a.md' =>
            page("```bash\necho '[2026-11-13T16:13:54.216Z] up'\n```\n\n```\n[2000-01-01 00:00:00 (UTC+0100)] up\n```\n") },
        status => 0,
        tap    => [qr/^ok 1 /m],
    },
    {
        name   => 'a timestamp with a fraction and a zone is normalized',
        files  => { 'docs/src/a.md' =>
            page("```bash\necho '2026-11-13 16:13:54.216 (UTC-0800) up'\n```\n\n```\n2000-01-01 00:00:00 up\n```\n") },
        status => 0,
        tap    => [qr/^ok 1 /m],
    },
    {
        name   => 'hashes of 40 and of 64 digits are normalized',
        files  => { 'docs/src/a.md' => page("```bash\nprintf '%s\\n%s\\n' 0123456789abcdef0123456789abcdef01234567 "
            . "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef\n```\n\n```\n"
            . "fedcba9876543210fedcba9876543210fedcba98\n"
            . "fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210\n```\n") },
        status => 0,
        tap    => [qr/^ok 1 /m],
    },
    {
        name   => 'a hash of 39 digits is compared as text',
        files  => { 'docs/src/a.md' => page("```bash\necho 0123456789abcdef0123456789abcdef0123456\n```\n\n```\n"
            . "fedcba9876543210fedcba9876543210fedcba9\n```\n") },
        status => 1,
        tap    => [qr/^not ok 1 /m],
    },
    {
        name   => 'elapsed and CPU times are normalized',
        files  => { 'docs/src/a.md' => page("```bash\necho 'Files=1, Tests=3,  5 wallclock secs ( 0.01 usr  0.00 sys)'\n```\n\n```\n"
            . "Files=1, Tests=3,  9 wallclock secs ( 1.50 usr  0.20 sys)\n```\n") },
        status => 0,
        tap    => [qr/^ok 1 /m],
    },
    {
        name   => 'process ids are normalized',
        files  => { 'docs/src/a.md' => page("```bash\necho 'pid 123 and PID=45'\n```\n\n```\npid 456 and PID=78\n```\n") },
        status => 0,
        tap    => [qr/^ok 1 /m],
    },
    {
        name   => 'ports of a URL are normalized and its host is not',
        files  => { 'docs/src/a.md' => page("```bash\necho 'opc.tcp://localhost:4840/x'\n```\n\n```\nopc.tcp://localhost:5000/x\n```\n") },
        status => 0,
        tap    => [qr/^ok 1 /m],
    },
    {
        name   => 'a host that differs is found',
        files  => { 'docs/src/a.md' => page("```bash\necho 'opc.tcp://localhost:4840/x'\n```\n\n```\nopc.tcp://example:4840/x\n```\n") },
        status => 1,
        tap    => [qr/^not ok 1 /m],
    },
    {
        name   => 'modification times of a listing are normalized',
        files  => { 'docs/src/a.md' => page("```bash\necho 'Nov 13 16:20 file'\n```\n\n```\nJan  2 03:04 file\n```\n") },
        status => 0,
        tap    => [qr/^ok 1 /m],
    },
    {
        name   => 'trailing blanks and final newlines are not compared',
        files  => { 'docs/src/a.md' => page("```bash\nprintf 'a  \\nb\\t\\n\\n\\n'\n```\n\n```\na\nb\n```\n") },
        status => 0,
        tap    => [qr/^ok 1 /m],
    },
    {
        name   => 'leading blanks of a line are compared',
        files  => { 'docs/src/a.md' => page("```bash\necho '  a'\n```\n\n```\na\n```\n") },
        status => 1,
        tap    => [qr/^not ok 1 /m],
    },
    {
        name   => 'the mode of a file is kept in the clean checkout',
        files  => { 'run.sh' => "#!/bin/sh\necho ran\n", 'docs/src/a.md' => page("```bash\n./run.sh\n```\n\n```\nran\n```\n") },
        modes  => { 'run.sh' => 0755 },
        status => 0,
        tap    => [qr/^ok 1 /m],
    },
    {
        name   => 'a ready text is a regular expression',
        files  => { 'docs/src/a.md' => page(
            "<!-- doc-check: background ready=value \\d+ -->\n"
            . "```bash\nsh -c 'trap \"exit 0\" INT; echo value 42; while :; do sleep 1; done'\n```\n\n```\nvalue 42\n```\n") },
        status => 0,
        tap    => [qr/^ok 1 /m],
    },
    {
        name   => 'the output of a background command only has to contain the page output',
        files  => { 'docs/src/a.md' => page(
            "<!-- doc-check: background ready=ready -->\n"
            . "```bash\nsh -c 'trap \"exit 0\" INT; echo noise; echo ready; echo more; while :; do sleep 1; done'\n```\n\n```\nready\n```\n") },
        status => 0,
        tap    => [qr/^ok 1 /m],
    },
    {
        name   => 'a background command whose output lacks the page output is found',
        files  => { 'docs/src/a.md' => page(
            "<!-- doc-check: background ready=ready -->\n"
            . "```bash\nsh -c 'trap \"exit 0\" INT; echo ready; while :; do sleep 1; done'\n```\n\n```\nabsent\n```\n") },
        status => 1,
        tap    => [qr/^not ok 1 /m, qr/output differs from the page/],
    },
    {
        name   => 'a command that fails with another status reports that status',
        files  => { 'docs/src/a.md' => page("```bash\nsh -c 'exit 3'\n```\n") },
        status => 1,
        tap    => [qr/exit status 3, expected 0/],
    },
    {
        name   => 'a page without a command and the summary page are not checked',
        files  => {
            'docs/src/a.md'       => page("Only text.\n"),
            'docs/src/SUMMARY.md' => "# Summary\n\n```bash\nfalse\n```\n",
        },
        status => 0,
        tap    => [qr/^1\.\.0$/m],
    },
);

for my $case (@cases) {
    my $tree = make_tree($case->{modes} || {}, %{ $case->{files} });
    my ($status, $stdout, $stderr) = run_tool($case->{ignore_int}, $tree, @{ $case->{args} || [] });
    is($status, $case->{status}, "$case->{name}: exit status");
    like($stdout, $_, "$case->{name}: TAP") for @{ $case->{tap} };
}

{
    my $tree = make_tree({}, 'docs/src/a.md' => page("```bash\ntrue\n```\n"));
    my ($status, undef, $stderr) = run_tool(0, $tree, '--no-such-option');
    is($status, 2, 'an unknown option is a usage error: exit status');
    like($stderr, qr/Unknown option/, 'an unknown option is a usage error: message');
    ($status, undef, $stderr) = run_tool(0, File::Spec->catdir($dir, 'does-not-exist'));
    is($status, 2, 'a missing tree is an error: exit status');
}

done_testing();
