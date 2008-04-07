#!/usr/bin/perl

BEGIN {
use File::Temp qw(tempdir);
$ENV{'PROPHET_REPO'} = tempdir( CLEANUP => 0 ) . '/repo-' . $$;

};

use Prophet::Test tests => 10;
use Test::WWW::Mechanize;
my $ua = Test::WWW::Mechanize->new();

my $cli = Prophet::CLI->new();
my $s = Prophet::TestServer->new();
$s->prophet_handle($cli->handle);

my $url_root = $s->started_ok("start up my web server");
sub url {
    return join("/",$url_root,@_);
}

$ua->get_ok(url('record-types.json'));
is($ua->content, '[]');

my $car = Prophet::Record->new(handle => $cli->handle, type => 'Cars');
my ($uuid) = $car->create(props => { wheels => 4, windshields => 1 });
ok($uuid, "Created record $uuid");

$ua->get_ok(url('record-types.json'));
is($ua->content, '["Cars"]');

$ua->get_ok(url('records','Cars',$uuid.".json"));
is($ua->content, '{"wheels":"4","windshields":"1"}');


$ua->post_ok(url('records','Cars',$uuid.".json"), { wheels => 6 } );

$ua->get_ok(url('records','Cars',$uuid.".json"));
is($ua->content, '{"wheels":"6","windshields":"1"}');

$ua->put(url('records','Cars.json'), { wheels => 3, seatbelts => 'sure!' } );

diag($ua->uri);
diag($ua->content);

package Prophet::Server;
use base qw/HTTP::Server::Simple::CGI/;
use Params::Validate qw/:all/;
use JSON;

sub prophet_handle {
    my $self = shift;
    $self->{'_prophet_handle'} = shift if (@_);
    return $self->{'_prophet_handle'};
}



sub handle_request {
    my $self = shift;
    my ($cgi) = validate_pos(@_, { isa=> 'CGI'});
    
    if (my $sub = $self->can('handle_request_'.lc($cgi->request_method))) {
        $sub->($self, $cgi);
    } else {
        warn "Sorry, I don't know how to handle ".$cgi->request_method." requests.";
    }   
}

sub handle_request_get {
    my $self = shift;
    my ($cgi) = validate_pos(@_, { isa=> 'CGI'});
    my $p = $cgi->path_info;  

    if ( $p =~ m|^/record-types.json| ) {
        print to_json($self->prophet_handle->enumerate_types); 

    } elsif ( $p =~ m|^/records/(.*)/(.*).json| ) {
        my $type = $1;
        my $uuid = $2;
        my $record = Prophet::Record->new( handle => $self->prophet_handle, type => $type);
        $record->load(uuid => $uuid);
        print to_json($record->get_props);
    }
}

sub handle_request_put {
    my $self = shift;
    my ($cgi) = validate_pos(@_, { isa=> 'CGI'});
    my $p = $cgi->path_info;  
    if ( $p =~ m|^/records/(.*).json| ) {
        my $type = $1;
        my $record = Prophet::Record->new( handle => $self->prophet_handle, type => $type);
        my $uuid = $record->create(props=> {map { $_ => $cgi->param($_) } $cgi->param()});
    
        print "302 Created\n";
        print "Location: /records/$type/$uuid.json";
    }

}
sub handle_request_post {
    my $self = shift;
    my ($cgi) = validate_pos(@_, { isa=> 'CGI'});
    my $p = $cgi->path_info;  
    if ( $p =~ m|^/records/(.*)/(.*).json| ) {
        my $type = $1;
        my $uuid = $2;
        my $record = Prophet::Record->new( handle => $self->prophet_handle, type => $type);
        $record->load(uuid => $uuid);
        my $ret = $record->set_props( props => {map { $_ => $cgi->param($_) } $cgi->param()});
        print "we should be returning some sort of resty code here";
    }
}




package Prophet::TestServer;
use base qw/Test::HTTP::Server::Simple Prophet::Server/;

1;
