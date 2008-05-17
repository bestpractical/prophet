use warnings;
use strict;
use Test::More tests => 5;

use File::Temp qw'tempdir';

use_ok('Prophet::CLI');
$ENV{'PROPHET_REPO'} = tempdir( CLEANUP => 0 ) . '/repo-' . $$;
my $cli = Prophet::CLI->new();
my $cxn = $cli->app_handle->handle;

my $record = Prophet::Record->new( handle => $cxn, type => 'Person' );
my $uuid = $record->create( props => { name => 'Jesse', age => 31 } );
ok($uuid, "got a record");
is( $record->prop('age'), 31 );
$record->set_prop( name => 'age', value => 32 );
is( $record->prop('age'), 32 );

$record->delete_prop(name => 'name');
is($record->prop('name'), undef, "no more name");

