#!/usr/bin/perl 
#
use warnings;
use strict;
use Prophet::Test 'no_plan';
use File::Temp qw/tempfile/;

$ENV{'PROPHET_APP_CONFIG'} = (tempfile(UNLINK => 1))[1];

use_ok('Prophet::CLI');
use_ok('Prophet::Config');
my $aliases = Prophet::Config->new(app_handle =>
        Prophet::CLI->new->app_handle)->aliases;

is_deeply( $aliases, {}, 'initial alias is empty' );

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
        comment => 'readd a new alias',
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
$aliases = Prophet::Config->new(app_handle =>
        Prophet::CLI->new->app_handle)->aliases;
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
alias pull -l = pull --local
alias pull -a = pull --all
EOF

