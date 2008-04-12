use warnings;
use strict;
use Test::More 'no_plan';
use File::Temp qw'tempdir';
use lib 't/lib';

use_ok('Prophet::Replica');
my $REPO = tempdir( CLEANUP => 0 ) . '/repo-' . $$;
ok( !-d $REPO );
`svnadmin create $REPO`;
ok( -d $REPO, "The repo exists ater svnadmin create" );
my $cxn = Prophet::Replica->new( {url  => "svn:file://$REPO"} );
isa_ok( $cxn, 'Prophet::Replica', "Got the cxn" );
use_ok('TestApp::Bug');

my $record = TestApp::Bug->new( handle => $cxn );

isa_ok( $record, 'TestApp::Bug' );
isa_ok( $record, 'Prophet::Record' );

my $uuid = $record->create( props => { name => 'Jesse', email => 'JeSsE@bestPractical.com' } );
ok($uuid);
is( $record->prop('email'), 'jesse@bestpractical.com' );

