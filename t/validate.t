use warnings;
use strict;

use Test::More tests => 7;
use File::Temp qw'tempdir';
use lib 't/lib';
use Test::Exception;


use_ok('Prophet::CLI');
$ENV{'PROPHET_REPO'} = tempdir( CLEANUP => 0 ) . '/repo-' . $$;
my $cli = Prophet::CLI->new();
my $cxn = $cli->app_handle->handle;
isa_ok( $cxn, 'Prophet::Replica', "Got the cxn" );
use_ok('TestApp::Bug');

my $record = TestApp::Bug->new( handle => $cxn );

isa_ok( $record, 'TestApp::Bug' );
isa_ok( $record, 'Prophet::Record' );

my $uuid = $record->create( props => { name => 'Jesse', age => 31 } );
ok($uuid);

throws_ok {
    $record->create( props => { name => 'Bob', age => 31 } );
}
qr/validation error/;
