#!/usr/bin/perl 
#
use warnings;
use strict;
use Prophet::Test 'no_plan';
use File::Temp qw/tempfile/;

$ENV{'PROPHET_APP_CONFIG'} = (tempfile())[1];

use_ok('Prophet::CLI');
use_ok('Prophet::Config');
my $aliases = Prophet::Config->new(app_handle =>
        Prophet::CLI->new->app_handle)->aliases;
# default aliases is empty
is_deeply( $aliases, {} );

my $out = run_command( 'aliases',
    '--add', q{pull -a=pull --all},
);

like($out, qr/added alias 'pull -a = pull --all'/);

unlink $ENV{'PROPHET_APP_CONFIG'};

#TODO XXX
#more tests soon
