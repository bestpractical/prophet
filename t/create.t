use warnings;
use strict;
use Test::More tests => 23;

use File::Temp qw'tempdir';

use_ok('Prophet::CLI');
$ENV{'PROPHET_REPO'} = tempdir( CLEANUP => ! $ENV{PROPHET_DEBUG}  ) . '/repo-' . $$;
my $cli = Prophet::CLI->new();
my $cxn = $cli->handle;

isa_ok( $cxn, 'Prophet::Replica', "Got the cxn" );

$cxn->initialize;

use_ok('Prophet::Record');
my $record = Prophet::Record->new( handle => $cxn, type => 'Person' );
isa_ok( $record, 'Prophet::Record' );
my $uuid = $record->create( props => { name => 'Jesse', age => 31 } );
ok($uuid);
is( $record->prop('age'), 31 );
$record->set_prop( name => 'age', value => 32 );
is( $record->prop('age'), 32 );

my $kaia = $record->create( props => { name => 'Kaia', age => 24 } );
ok($kaia);
my $mao = $record->create( props => { name => 'Mao', age => 0.7, species => 'cat' } );
ok($mao);
my $mei = $record->create( props => { name => 'Mei', age => "0.7", species => 'cat' } );
ok($mei);
use_ok('Prophet::Collection');

my $people = Prophet::Collection->new( handle => $cxn, type => 'Person' );
$people->matching( sub { ( shift->prop('species') || '' ) ne 'cat' } );
is( $people->count, 2 );
is_deeply( [ sort map { $_->prop('name') } @$people ], [qw(Jesse Kaia)] );

my $cats = Prophet::Collection->new( handle => $cxn, type => 'Person' );
$cats->matching( sub { ( shift->prop('species') || '' ) eq 'cat' } );
is( $cats->count , 2 );
for (@$cats) {
    is( $_->prop('age'), "0.7" );
}
is_deeply( [ sort map { $_->prop('name') } @$cats ], [qw(Mao Mei)] );

my $cat = Prophet::Record->new( handle => $cxn, type => 'Person' );
$cat->load( uuid => $mao );
$cat->set_prop( name => 'age', value => '0.8' );
my $cat2 = Prophet::Record->new( handle => $cxn, type => 'Person' );
$cat2->load( uuid => $mei );
$cat2->set_prop( name => 'age', value => '0.8' );

# Redo our search for cats
$cats = Prophet::Collection->new( handle => $cxn, type => 'Person' );
$cats->matching( sub { ( shift->prop('species') || '' ) eq 'cat' } );
is( $cats->count, 2 );
for (@$cats) {
    is( $_->prop('age'), "0.8" );
}

for (@$cats) {
    ok( $_->delete );
}

my $records = Prophet::Collection->new( type => 'Person', handle => $cxn );
$records->matching( sub {1} );
is( $records->count, 2 );
1;
