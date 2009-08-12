#!/usr/bin/perl 
#
use warnings;
use strict;
use Prophet::Test tests => 13;
use File::Copy;
use File::Temp qw'tempdir';
use File::Spec;

my $repo = $ENV{'PROPHET_REPO'} =
  File::Spec->catdir( $Prophet::Test::REPO_BASE, "repo-$$" );

# since we don't initialize the db for these tests, make the repo dir
mkdir $ENV{PROPHET_REPO};

use_ok('Prophet::CLI');

# load up a prophet app instance

my $a = Prophet::CLI->new();
can_ok($a, 'app_handle');
can_ok($a->app_handle, 'config');
my $c = $a->config;

$c->load;

is( $c->config_files->[0], undef, 'no config files loaded' );

# interrogate its config to see if we have any config options set
my @keys = $c->dump;
is( scalar @keys, 0, 'no config options are set' );

# set a config file 
{
    copy 't/test_app.conf', $repo;
    local $ENV{'PROPHET_APP_CONFIG'}
        = File::Spec->catfile($repo,'test_app.conf');

    my $app_handle = Prophet::CLI->new->app_handle;
    my $conf = Prophet::Config->new(
        app_handle => $app_handle,
        handle => $app_handle->handle,
        confname => 'testrc',
    );
    $conf->load;
    # make sure we only have the one test config file loaded
    is( length @{$conf->config_files}, 1, 'only test conf is loaded' );

    # interrogate its config to see if we have any config options set
    my @data = $conf->dump;
    is( scalar @data, 6, '3 config options are set' );
    # test the aliases sub
    is( $conf->aliases->{tlist}, 'ticket list', 'Got correct alias' );
    # test automatic reload after setting
    $conf->set(
        key => 'replica.sd.url',
        value => 'http://fsck.com/sd/',
        filename => File::Spec->catfile($repo, 'test_app.conf'),
    );
    is( $conf->get( key => 'replica.sd.url' ), 'http://fsck.com/sd/',
        'automatic reload after set' );
    # test the sources sub
    is( $conf->sources->{sd}, 'http://fsck.com/sd/', 'Got correct alias' );
    is( $conf->sources( by_variable => 1)->{'http://fsck.com/sd/'},
        'sd',
        'Got correct alias',
    );
    # test the display_name_for_replica sub
    $conf->set(
        key => 'replica.sd.uuid',
        value => '32b13934-910a-4792-b5ed-c9977b212245',
        filename => File::Spec->catfile($repo, 'test_app.conf'),
    );
    is( $app_handle->display_name_for_replica('32b13934-910a-4792-b5ed-c9977b212245'),
        'sd',
        'Got correct display name'
    );

    # run the cli "config" command
    # make sure it matches with our file
    my $got = run_command('config');
    my $expect = <<EOF;
Configuration:

Config files:

EOF
    $expect .= File::Spec->catfile( $repo, 'test_app.conf' ) . "\n";
    $expect .= <<EOF;

Your configuration:

alias.tlist=ticket list
core.config-format-version=0
replica.sd.url=http://fsck.com/sd/
replica.sd.uuid=32b13934-910a-4792-b5ed-c9977b212245
test.foo=bar
test.re=rawr
EOF
    is($got, $expect, 'output of config command');
}
