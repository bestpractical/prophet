#!/usr/bin/perl 
#
use warnings;
use strict;
use Prophet::Test 'no_plan';
use File::Temp qw/tempdir tempfile/;

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

my @cmds = (
    {
        cmd => [ '--add', 'pull -a=pull --all' ],
        output  => qr/added alias 'pull -a = pull --all/,
        comment => 'add a new alias',
    },
    {
        cmd => [ '--add', 'pull -a=pull --all' ],
        output  => qr/alias 'pull -a = pull --all' isn't changed, won't update/,
        comment => 'add the same alias will not change anything',
    },
    {

        # this alias is bad, please don't use it in real life
        cmd => [ '--set', 'pull -a=pull --local' ],
        output =>
          qr/changed alias 'pull -a' from 'pull --all' to 'pull --local'/,
        comment =>
          q{changed alias 'pull -a' from 'pull --all' to 'pull --local'},
    },
    {
        cmd     => [ '--delete', 'pull -a' ],
        output  => qr/deleted alias 'pull -a = pull --local'/,
        comment => q{deleted alias 'pull -a = pull --local'},
    },
    {
        cmd     => [ '--delete', 'pull -a' ],
        output  => qr/didn't find alias 'pull -a'/,
        comment => q{delete an alias that doesn't exist any more},
    },
    {
        cmd => [ '--add', 'pull -a=pull --all' ],
        output  => qr/added alias 'pull -a = pull --all/,
        comment => 'read a new alias',
    },
    {
        cmd => [ '--add', 'pull -l=pull --local' ],
        output  => qr/added alias 'pull -l = pull --local/,
        comment => 'add a new alias',
    },
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
EOF

# TODO: need tests for interactive alias editing
