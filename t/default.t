use warnings;
use strict;
use Test::More tests => 9;
use File::Temp qw'tempdir';
use lib 't/lib';

use_ok('Prophet::CLI');
$ENV{'PROPHET_REPO'} = tempdir( CLEANUP => ! $ENV{PROPHET_DEBUG}  ) . '/repo-' . $$;
my $cli = Prophet::CLI->new();
my $cxn = $cli->handle;
$cxn->initialize;
isa_ok($cxn, 'Prophet::Replica');

use_ok('TestApp::Bug');

my $record = TestApp::Bug->new( handle => $cxn );

isa_ok( $record, 'TestApp::Bug' );
isa_ok( $record, 'Prophet::Record' );

my $uuid = $record->create( props => { name => 'Jesse', email => 'JeSsE@bestPractical.com' } );
ok($uuid);
is( $record->prop('status'), 'new', "default status" );

my $closed_record = TestApp::Bug->new( handle => $cxn );

$uuid = $closed_record->create( props => { name => 'Jesse', email => 'JeSsE@bestPractical.com', status => 'closed' } );
ok($uuid);
is( $closed_record->prop('status'), 'closed', "default status is overridable" );

