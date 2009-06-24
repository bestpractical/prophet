#!/usr/bin/perl 
#
use warnings;
use strict;
use Prophet::Test tests => 30;
use File::Temp qw/tempfile/;

$ENV{'PROPHET_REPO'} = $Prophet::Test::REPO_BASE . '/repo-' . $$;
$ENV{'PROPHET_APP_CONFIG'} = (tempfile(UNLINK => !$ENV{PROPHET_DEBUG}))[1];
diag("Using config file $ENV{PROPHET_APP_CONFIG}");

# since we don't initialize the db for these tests, make the repo dir
mkdir $ENV{PROPHET_REPO};

use_ok('Prophet::CLI');
use_ok('Prophet::Config');

my $config = Prophet::CLI->new()->config;
$config->load;

is_deeply( scalar $config->aliases, {}, 'initial alias is empty' );

# no news is good news
my @cmds = (
    {
        cmd => [ 'show' ],
        output  => qr/^No aliases for the current repository.\n$/,
        comment => 'show empty aliases',
    },

    {
        cmd => [ 'add', 'pull -a=pull --all' ],
        output  => qr//,
        comment => 'add a new alias',
    },
    {
        cmd => [ 'pull -a' ],
        output  => qr/pull --all/,
        comment => 'new alias set correctly',
    },
    {
        # this alias is bad, please don't use it in real life
        cmd => [ 'set', 'pull -a=pull --local' ],
        output => qr//,
        comment =>
          q{changed alias 'pull -a' from 'pull --all' to 'pull --local'},
    },
    {
        cmd => [ 'pull -a' ],
        output  => qr/pull --local/,
        comment => 'alias changed correctly',
    },
    {
        cmd     => [ 'delete', 'pull -a' ],
        output  => qr//,
        comment => q{deleted alias 'pull -a = pull --local'},
    },
    {
        cmd     => [ 'delete', 'pull -a' ],
        output  => qr//,
        comment => q{delete an alias that doesn't exist any more},
    },
    {
        cmd => [ 'add', 'pull -a=pull --all' ],
        output  => qr//,
        comment => 'add a new alias',
    },
    {
        cmd => [ 'pull -a' ],
        output  => qr/pull --all/,
        comment => 'alias is set correctly',
    },
    {
        cmd => [ 'add', 'pull -l=pull --local' ],
        output  => qr//,
        comment => 'add a new alias',
    },
    {
        cmd => [ 'pull -l' ],
        output  => qr/pull --local/,
        comment => 'alias is set correctly',
    },
    {
        cmd => [ 'show' ],
        output  => qr/Active aliases for the current repository \(including user-wide and global\naliases if not overridden\):\n\npull -l = pull --local\npull -a = pull --all/s,
        comment => 'show',
    },
    {
        cmd => [ 'add', 'foo', 'bar', '=', 'bar',  'baz' ],
        output  => qr//,
        comment => 'added alias foo bar',
    },
    {
        cmd => [ 'foo bar' ],
        output  => qr/bar baz/,
        comment => 'alias is set correctly',
    },
    {
        cmd => [ 'foo', 'bar', '=bar',  'baz' ],
        output  => qr//,
        comment => 'read alias foo bar',
    },
    {
        cmd => [ 'foo bar' ],
        output  => qr/bar baz/,
        comment => 'alias foo bar still the same',
    },
    {
        cmd => [ 'delete', 'foo', 'bar' ],
        output  => qr//,
        comment => 'deleted alias foo bar',
    },
    {
        cmd => [ 'foo', 'bar' ],
        output  => qr//,
        comment => 'deleted alias no longer exists',
    },
    {
        cmd => [ 'set', 'foo', 'bar', '=', 'bar baz'],
        output => qr//,
        comment => 'set alias again with different syntax',
    },
    # tests for alternate syntax
    {
        cmd => [ 'foo bar', 'bar baz'],
        output  => qr//,
        comment => 'alias foo bar = bar baz didn\'t change',
    },
    {
        cmd => [ 'foo', 'bar baz'],
        output  => qr//,
        comment => 'added alias foo',
    },
    {
        cmd => [ 'foo' ],
        output  => qr/bar baz/,
        comment => 'alias foo set correctly',
    },
    {
        cmd => [ 'foo bar', 'bar'],
        output => qr//,
        comment => 'changed alias foo bar',
    },
    {
        cmd => [ 'pull --from http://www.example.com/', 'pfe'],
        output => qr//,
        comment => 'added alias with weird characters',
    },
    {
        cmd => [ 'pull --from http://www.example.com/'],
        output => qr/pfe/,
        comment => 'alias with weird chars is correct',
    },
,
);

for my $item ( @cmds ) {
    my $out = run_command( 'aliases', @{$item->{cmd}} );
    like( $out, $item->{output}, $item->{comment} );
}


# check aliases in config
my $aliases = Prophet::Config->new(
    app_handle => Prophet::CLI->new->app_handle,
    confname => 'testrc'
)->aliases;

is_deeply(
    $aliases,
    {
        'pull -l' => 'pull --local',
        'pull -a' => 'pull --all',
        'foo bar' => 'bar',
        'foo' => 'bar baz',
        'pull --from http://www.example.com/' => 'pfe',
    },
    'non empty aliases',
);

# check content in config
my $content;
open my $fh, '<', $ENV{'PROPHET_APP_CONFIG'}
  or die "failed to open $ENV{'PROPHET_APP_CONFIG'}: $!";
{ local $/; $content = <$fh>; }
is( $content, <<EOF, 'content in config' );

[alias]
	pull -a = pull --all
	pull -l = pull --local
	foo = bar baz
	foo bar = bar
	pull --from http://www.example.com/ = pfe
EOF

# TODO: need tests for interactive alias editing
