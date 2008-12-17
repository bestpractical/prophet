use warnings;
use strict;
use Test::More  tests => 7;
use File::Temp qw'tempdir';
use lib 't/lib';



use_ok('Prophet::CLI');
$ENV{'PROPHET_REPO'} = tempdir( CLEANUP => ! $ENV{PROPHET_DEBUG}  ) . '/repo-' . $$;
my $cli = Prophet::CLI->new();
my $cxn = $cli->handle;
isa_ok($cxn, 'Prophet::Replica');

$cxn->initialize;

use_ok('TestApp::Bug');

my $record = TestApp::Bug->new( handle => $cxn );

isa_ok( $record, 'TestApp::Bug' );
isa_ok( $record, 'Prophet::Record' );

my $uuid = $record->create( props => { name => 'Jesse', email => 'JeSsE@bestPractical.com' } );
ok($uuid);
is( $record->prop('email'), 'jesse@bestpractical.com' );

