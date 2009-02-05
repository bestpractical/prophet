use warnings;
use strict;
use Test::More tests => 7;
use lib 't/lib';

use File::Temp qw'tempdir';

# test coverage for Prophet::Record references (subs register_reference,
# register_collection_reference, and register_record_reference)

use_ok('Prophet::CLI');
$ENV{'PROPHET_REPO'} = tempdir( CLEANUP => ! $ENV{PROPHET_DEBUG}  ) . '/repo-' . $$;

my $cli = Prophet::CLI->new();
my $cxn = $cli->handle;
my $app = $cli->app_handle;
isa_ok( $cxn, 'Prophet::Replica', "Got the cxn" );

$cxn->initialize;

use_ok('TestApp::ButterflyNet');
my $net = TestApp::ButterflyNet->new( handle => $cxn );
$net->create( props => { catches => 'butterflies' } );

use_ok('TestApp::BugCatcher');
my $bugcatcher = TestApp::BugCatcher->new( app_handle => $app, handle => $cxn );
$bugcatcher->create( props => { net => $net->uuid, name => 'Larry' } );

use_ok('TestApp::Bug');
my $monarch = TestApp::Bug->new( handle => $cxn );
$monarch->create( props => { bugcatcher => $bugcatcher->uuid, species =>
        'monarch' } );
my $viceroy = TestApp::Bug->new( handle => $cxn );
$viceroy->create( props => { bugcatcher => $bugcatcher->uuid, species =>
        'viceroy' } );

# test collection reference
my @got = map { $_->uuid }
          sort { $a->uuid cmp $b->uuid }
          @{$bugcatcher->bugs};

my @expected = map { $_->uuid }
               sort { $a->uuid cmp $b->uuid }
               ($monarch, $viceroy);

is_deeply(\@got, \@expected, "collection's record uuids match");

# test record reference
is($bugcatcher->net->uuid, $net->uuid);
