#!/usr/bin/perl 
#
use warnings;
use strict;
use Prophet::Test 'no_plan';
use File::Temp qw'tempdir';
    $ENV{'PROPHET_REPO'} = tempdir( CLEANUP => ! $ENV{PROPHET_DEBUG}  ) . '/repo-' . $$;
delete $ENV{'PROPHET_APP_CONFIG'};

use_ok('Prophet::CLI');
# Test basic config file parsing
use_ok('Prophet::Config');
my $config = Prophet::Config->new(app_handle => Prophet::CLI->new->app_handle);

isa_ok($config => 'Prophet::Config');
can_ok($config  => 'load_from_files');

can_ok($config, 'get');
can_ok($config, 'set');
can_ok($config, 'list');
can_ok($config, 'aliases');

is($config->get('_does_not_exist'), undef);
is($config->set('_does_not_exist' => 'hey you!'), 'hey you!');
is($config->get('_does_not_exist'), 'hey you!');
is_deeply([$config->list], ['_does_not_exist'], "The deep structures match");

# load up a prophet app instance


my $a = Prophet::CLI->new();
can_ok($a, 'app_handle');
can_ok($a->app_handle, 'config');
my $c = $a->config;

# interrogate its config to see if we have any config options set
my @keys = $c->list;
is (scalar @keys,0);

# set a config file 
{ local $ENV{'PROPHET_APP_CONFIG'} = 't/test_app.conf';
my $conf = Prophet::Config->new(app_handle => Prophet::CLI->new->app_handle);
# interrogate its config to see if we have any config options set
my @keys = $conf->list;
is (scalar @keys,4);
# test the alias
is($conf->aliases->{tlist}, "ticket list", "Got correct alias");
}


# run the cli "show config" command 
# make sure it matches with our file
