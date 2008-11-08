use warnings;
use strict;
use Test::More tests => 4;
use Test::Exception;

use File::Temp qw'tempdir';

use_ok('Prophet::CLI');
$ENV{'PROPHET_REPO'} = tempdir( CLEANUP => 0 ) . '/repo-' . $$;
my $cli = Prophet::CLI->new();
my $cxn = $cli->handle;

isa_ok( $cxn, 'Prophet::Replica', "Got the cxn" );

lives_ok {
    $cxn->initialize;
} "initialize the connection";

throws_ok {
    $cxn->initialize;
} qr/The replica is already initialized/, "attempting to reinitialize a replica throws an error";

1;

