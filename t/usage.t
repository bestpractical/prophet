#!/usr/bin/perl
use warnings;
use strict;

use Prophet::Test tests => 72;
use File::Temp qw(tempdir);

$ENV{'PROPHET_REPO'} = tempdir( CLEANUP => ! $ENV{PROPHET_DEBUG}  ) . '/repo-' . $$;
diag "Replica is in $ENV{PROPHET_REPO}";

# command usage messages

my @cmds = (
    {
        cmd     => [ 'config', '-h' ],
        error   => [
            'usage: usage.t config [show]',
            '       usage.t config edit [--global|--user]',
            '       usage.t config <section.subsection.var> [<value>]',
            ],
        comment => 'config usage',
    },
    {
        cmd     => [ 'config', 'add' ],
        error   => ['usage: usage.t config add section.subsection.var ["key value"]'],
        comment => 'config add usage',
    },
    {
        cmd     => [ 'config', 'delete' ],
        error   => [ 'usage: usage.t config delete section.subsection.var' ],
        comment => 'config delete usage',
    },
    {
        cmd     => [ 'alias', '-h' ],
        error   => [
            'usage: usage.t aliases [show]',
            '       usage.t aliases edit [--global|--user]',
            '       usage.t alias <alias text> [<text to translate to>]',
                ],
        comment => 'alias usage',
    },
    {
        cmd     => [ 'alias', 'add'  ],
        error   => [ 'usage: usage.t alias add "alias text" "cmd to translate to"' ],
        comment => 'alias add usage',
    },
    {
        cmd     => [ 'aliases', 'add' ],
        error   => [ 'usage: usage.t aliases add "alias text" "cmd to translate to"' ],
        comment => 'aliases add usage',
    },
    {
        cmd     => [ 'alias', 'delete' ],
        error   => [ 'usage: usage.t alias delete "alias text"' ],
        comment => 'alias delete usage',
    },
    {
        cmd     => [ 'clone', '-h' ],
        error   => [ 'usage: usage.t clone --from <url> | --local' ],
        comment => 'clone usage',
    },
    {
        cmd     => [ 'create', '-h' ],
        error   => [ 'usage: usage.t create <record-type> -- prop1=foo prop2=bar' ],
        comment => 'create usage',
    },
    {
        cmd     => [ 'new', '-h' ],
        error   => [ 'usage: usage.t new <record-type> -- prop1=foo prop2=bar' ],
        comment => 'new usage (alias of create)',
    },
    {
        cmd     => [ 'delete', '-h' ],
        error   => [ 'usage: usage.t delete <record-type> <id>' ],
        comment => 'delete usage',
    },
    {
        cmd     => [ 'rm', '-h' ],
        error   => [ 'usage: usage.t rm <record-type> <id>' ],
        comment => 'rm usage (alias of delete)',
    },
    {
        cmd     => [ 'export', '-h' ],
        error   => [ 'usage: usage.t export --path <path> [--format feed]' ],
        comment => 'export usage',
    },
    {
        cmd     => [ 'export' ],
        error   => [
            'No --path argument specified!',
            'usage: usage.t export --path <path> [--format feed]'
        ],
        comment => 'export usage with error',
    },
    {
        cmd     => [ 'history', '-h' ],
        error   => [ 'usage: usage.t history <record-type> <record>' ],
        comment => 'history usage',
    },
    {
        cmd     => [ 'info', '-h' ],
        error   => [ 'usage: usage.t info' ],
        comment => 'info usage',
    },
    {
        cmd     => [ 'init', '-h' ],
        error   => [ 'usage: usage.t init' ],
        comment => 'init usage',
    },
    {
        cmd     => [ 'log', '-h' ],
        error   => [
            'usage: usage.t log --all              Show all entries',
            '       usage.t log 0..LATEST~5        Show first entry up until the latest',
            '       usage.t log LATEST~10          Show last ten entries',
            '       usage.t log LATEST             Show last entry',
        ],
        comment => 'log usage',
    },
    {
        cmd     => [ 'merge', '-h' ],
        error   => [
            'usage: usage.t merge --from <replica> --to <replica> [options]',
            '',
            'Options are:',
            '    -v|--verbose            Be verbose',
            '    -f|--force              Do merge even if replica UUIDs differ',
            "    -n|--dry-run            Don't actually import changesets",
        ],
        comment => 'merge usage',
    },
    {
        cmd     => [ 'mirror', '-h' ],
        error   => [ 'usage: usage.t mirror --from <url>' ],
        comment => 'mirror usage',
    },
    {
        cmd     => [ 'mirror' ],
        error   => [
            'No --from specified!',
            'usage: usage.t mirror --from <url>',
        ],
        comment => 'mirror usage with error',
    },
    {
        cmd     => [ 'publish', '-h' ],
        error   => [ 'usage: usage.t publish --to <location|name> [--html] [--replica]' ],
        comment => 'publish usage',
    },
    {
        cmd     => [ 'publish' ],
        error   => [
            'No --to specified!',
            'usage: usage.t publish --to <location|name> [--html] [--replica]',
        ],
        comment => 'publish usage with error',
    },
    {
        cmd     => [ 'pull', '-h' ],
        error   => [
            'usage: usage.t pull --from <url|name>',
            '       usage.t pull --all',
            '       usage.t pull --local',
        ],
        comment => 'pull usage',
    },
    {
        cmd     => [ 'pull' ],
        error   => [
            'No --from, --local, or --all specified!',
            'usage: usage.t pull --from <url|name>',
            '       usage.t pull --all',
            '       usage.t pull --local',
        ],
        comment => 'pull usage with error',
    },
    {
        cmd     => [ 'push', '-h' ],
        error   => [ 'usage: usage.t push --to <url|name> [--force]' ],
        comment => 'push usage',
    },
    {
        cmd     => [ 'push' ],
        error   => [
            'No --to specified!',
            'usage: usage.t push --to <url|name> [--force]',
        ],
        comment => 'push usage with error',
    },
    {
        cmd     => [ 'search', '-h' ],
        error   => [
            'usage: usage.t search <record-type>',
            '       usage.t search <record-type> -- prop1=~foo prop2!~bar|baz',
        ],
        comment => 'search usage',
    },
    {
        cmd     => [ 'list', '-h' ],
        error   => [
            'usage: usage.t list <record-type>',
            '       usage.t list <record-type> -- prop1=~foo prop2!~bar|baz',
        ],
        comment => 'list usage',
    },
    {
        cmd     => [ 'settings', '-h' ],
        error   => [
            'usage: usage.t settings [show]',
            '       usage.t settings edit',
            '       usage.t settings set -- setting "new value"',
            '',
            'Note that setting values must be valid JSON.',
        ],
        comment => 'settings usage',
    },
    {
        cmd     => [ 'shell', '-h' ],
        error   => [ 'usage: usage.t [shell]' ],
        comment => 'shell usage',
    },
    {
        cmd     => [ 'show', '-h' ],
        error   => [ 'usage: usage.t show <record-type> <record-id> [--batch] [--verbose]' ],
        comment => 'show usage',
    },
    {
        cmd     => [ 'show' ],
        error   => [
            'No UUID or LUID given!',
            'usage: usage.t show <record-type> <record-id> [--batch] [--verbose]',
        ],
        comment => 'show usage with error',
    },
    {
        cmd     => [ 'update', '-h' ],
        error   => [
            'usage: usage.t update <record-type> <record-id> --edit',
            '       usage.t update <record-type> <record-id> -- prop1="new value"',
        ],
        comment => 'update usage',
    },
    {
        cmd     => [ 'edit', '-h' ],
        error   => [
            'usage: usage.t edit <record-type> <record-id> --edit',
            '       usage.t edit <record-type> <record-id> -- prop1="new value"',
        ],
        comment => 'edit usage',
    },
    {
        cmd     => [ 'update' ],
        error   => [
            'No UUID or LUID given!',
            'usage: usage.t update <record-type> <record-id> --edit',
            '       usage.t update <record-type> <record-id> -- prop1="new value"',
        ],
        comment => 'update usage with error',
    },
);

my $in_interactive_shell = 0;

for my $item ( @cmds ) {
    my $exp_error
        = defined $item->{error}
        ? (join "\n", @{$item->{error}}) . "\n"
        : '';
    my ($got_output, $got_error) = run_command( @{$item->{cmd}} );
    is( $got_error, $exp_error, $item->{comment} );
}

$in_interactive_shell = 1;

for my $item ( @cmds ) {
    my $exp_error
        = defined $item->{error}
        ? (join "\n", @{$item->{error}}) . "\n"
        : '';
    # in an interactive shell, usage messages shouldn't be printing a command
    # name
    $exp_error =~ s/usage.t //g;
    my ($got_output, $got_error) = run_command( @{$item->{cmd}} );
    is( $got_error, $exp_error, $item->{comment} );
}

no warnings 'redefine';
sub Prophet::CLI::interactive_shell {
    return $in_interactive_shell;
}

