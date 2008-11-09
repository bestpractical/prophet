package Prophet::Server;
use Moose;
extends qw'HTTP::Server::Simple::CGI';

use Prophet::Server::View;
use Prophet::Server::Dispatcher;
use Params::Validate qw/:all/;
use JSON;

has app_handle => ( isa => 'Prophet::App', is => 'rw',
    handles => [ qw/handle/]
);

has cgi => (isa => 'Maybe[CGI]', is => 'rw');
has read_only => ( is => 'rw', isa => 'Bool');

before run => sub {
    my $self      = shift;
    my $publisher = eval {
        require Net::Rendezvous::Publish;
        Net::Rendezvous::Publish->new;
    };
    if ($publisher) {
        $publisher->publish(
            name   => $self->handle->db_uuid,
            type   => '_prophet._tcp',
            port   => $self->port,
            domain => 'local',
        );
    } else {
        warn 
            "Publisher backend is not available. Install one of the ".
            "Net::Rendezvous::Publish::Backend modules from CPAN.";
    }
};

sub setup_template_roots {
    my $self = shift;
    my $view_class = ref( $self->app_handle ) . "::Server::View";

    if ( Prophet::App->try_to_require($view_class) ) {
        Template::Declare->init( roots => [$view_class] );

    }
    else {
        Template::Declare->init( roots => ['Prophet::Server::View'] );
    }
}

override handle_request => sub {
    my ($self, $cgi) = validate_pos( @_, { isa => 'Prophet::Server'} ,  { isa => 'CGI' } );
    $self->cgi($cgi);
    
   
    my $d = Prophet::Server::Dispatcher->new(server => $self);
   $d->run($cgi->request_method."/". $cgi->path_info, $self) || $self->_send_404;

};



sub load_record {
    my $self = shift;
    my %args = validate( @_, { type => 1, uuid => 0 } );
    require Prophet::Record;
    my $record = Prophet::Record->new( handle => $self->handle, type => $args{type} );
    if ( $args{'uuid'} ) {
        return undef unless ( $self->handle->record_exists( type => $args{'type'}, uuid => $args{'uuid'} ) );
        $record->load( uuid => $args{uuid} );
    }
    return $record;
}

sub send_content {
    my $self = shift;
    my %args = validate( @_, { content => 1, content_type => 0, encode_as => 0 } );

    if ($args{'encode_as'} && $args{'encode_as'} eq 'json') {
        $args{'content_type'} = 'text/x-json'; 
        $args{'content'} = to_json($args{'content'});
    }

    print "HTTP/1.0 200 OK\r\n";
    print "Content-Type: " . $args{'content_type'} . "\r\n";
    print "Content-Length: " . length( $args{'content'} ) . "\r\n\r\n";
    print $args{'content'};
    return '200';
}

sub _send_401 {
    my $self = shift;
    print "HTTP/1.0 401 READONLY_SERVER\r\n";
    return '401';
}

sub _send_404 {
    my $self = shift;
    print "HTTP/1.0 404 ENOFILE\r\n";
    return '404';
}

sub _send_redirect {
    my $self = shift;
    my %args = validate( @_, { to => 1 } );
    print "HTTP/1.0 302 Go over there\r\n";
    print "Location: " . $args{'to'} . "\r\n";
    return '302';
}

1;
