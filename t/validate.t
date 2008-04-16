use warnings;
use strict;

use Test::More tests => 7;
use File::Temp qw'tempdir';
use lib 't/lib';
use Test::Exception;

my $SCHEME = $ENV{'PROPHET_REPLICA_TYPE'} || 'svn';

use_ok('Prophet::Replica');
my $REPO = tempdir( CLEANUP => 0 ) . '/repo-' . $$;
my $cxn = Prophet::Replica->new( { url => "$SCHEME:file://$REPO" });
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
