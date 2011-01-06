#!/usr/bin/perl
use warnings;
use strict;

BEGIN {
    use File::Temp qw(tempdir);
    $ENV{'PROPHET_REPO'} = tempdir( CLEANUP => ! $ENV{PROPHET_DEBUG}  ) . '/repo-' . $$;

}

use Prophet::Test;
BEGIN {
    eval { require Test::WWW::Mechanize; require Test::HTTP::Server::Simple }
        || plan skip_all => "This test file requires Test::WWW::Mechanize and Test::HTTP::Server::Simple";
}



plan tests => 26;
use JSON;

use_ok('Prophet::Record');

my $ua  = Test::WWW::Mechanize->new();
my $cli = Prophet::CLI->new();

$cli->handle()->initialize;

my $s = Prophet::TestServer->new( app_handle => $cli->app_handle );

my $url_root = $s->started_ok("start up my web server");

sub url {
    return join( "/", $url_root, @_ );
}
diag(url());
$ua->get_ok( url('records.json') );
is( $ua->content, '[]' );

my $car = Prophet::Record->new( handle => $cli->handle, type => 'Cars' );
my ($uuid) = $car->create( props => { wheels => 4, windshields => 1 } );
ok( $uuid, "Created record $uuid" );

$ua->get_ok( url('records.json') );
is( $ua->content, '["Cars"]' );

$ua->get_ok( url( 'records', 'Cars', $uuid . ".json" ) );
is_deeply(
    from_json( $ua->content ),
    from_json(
            '{"original_replica":"'
          . $car->handle->uuid
          . '","creator":"'
          . $car->default_prop_creator
          . '","wheels":"4","windshields":"1"}'
    )
);

$ua->get( url( 'records', 'Cars', "1234.json" ) );
is( $ua->status, '404' );

$ua->post_ok( url( 'records', 'Cars', $uuid . ".json" ), { wheels => 6 } );

$ua->get_ok( url( 'records', 'Cars', $uuid . ".json" ) );

is_deeply(
    from_json( $ua->content ),
    from_json(
            '{"original_replica":"'
          . $car->handle->uuid
          . '","creator":"'
          . $car->default_prop_creator
          . '","wheels":"6","windshields":"1"}'
    )
);

$ua->post( url( 'records', 'Cars', "doesnotexist.json" ), { wheels => 6 } );
is( $ua->status, '404', "Can't update a nonexistant car" );

$ua->post_ok( url( 'records', 'Cars.json' ), { wheels => 3, seatbelts => 'sure!' } );
my $new_uuid;
if ( $ua->uri =~ /Cars\/(.*)\.json/ ) {
    $new_uuid = $1;
    ok( $new_uuid, "Got the new record's uuid" );

} else {
    ok( 0, "Failed to get the new record's uri" );
}

my $car2 = Prophet::Record->new( handle => $cli->handle, type => 'Cars' );
$car2->load( uuid => $new_uuid );
is_deeply( $car2->get_props, {
    creator => $car2->default_prop_creator,
    wheels => 3,
    seatbelts => 'sure!',
    original_replica => $car2->handle->uuid,
}, "The thing we created remotely worked just great" );

diag("testing property-level access");
$ua->get_ok( url( 'records', 'Cars', $uuid, 'wheels' ) );
is( $ua->content, '6' );

$ua->post( url( 'records', 'Cars', $uuid, 'wheels' ), { value => 5 } );
is( $ua->content, '5', "Performing the update we get back the new response" );
diag( $ua->uri );
$ua->get_ok( url( 'records', 'Cars', $uuid, 'wheels' ) );
is( $ua->content, '5', "The update worked" );

$ua->get( url( 'records', 'Cars', $uuid, 'elephants' ) );
is( $ua->status, '404', "A car has no elephants yet, so the property returns 0" );

diag("Now fetching a list of all the cars on the road");
$ua->get_ok( url( 'records', 'Cars.json' ) );
is_deeply(
    from_json( $ua->content ),
    {   $uuid     => '/records/Cars/' . $uuid . '.json',
        $new_uuid => '/records/Cars/' . $new_uuid . '.json',
    }
);

$ua->get( url('some_crazy_page') );
is( $ua->status, '404', "No that page doesn't exist" );

package Prophet::TestServer;
use base qw/Test::HTTP::Server::Simple Prophet::Server/;


sub port { my $self = shift; $self->{_port} ||= int(rand(1024))+10000; return $self->{_port} }
1;
