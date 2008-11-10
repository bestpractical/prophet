package Prophet::Server;
use Moose;
extends qw'HTTP::Server::Simple::CGI';

use Prophet::Server::View;
use Prophet::Server::Dispatcher;
use Params::Validate qw/:all/;
use JSON;

has app_handle => (
    isa     => 'Prophet::App',
    is      => 'rw',
    handles => [qw/handle/]
);

has cgi       => ( isa => 'Maybe[CGI]', is  => 'rw' );
has read_only => ( is  => 'rw',         isa => 'Bool' );

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
        warn "Publisher backend is not available. Install one of the "
            . "Net::Rendezvous::Publish::Backend modules from CPAN.";
    }
};

sub setup_template_roots {
    my $self       = shift;
    my $view_class = ref( $self->app_handle ) . "::Server::View";

    if ( Prophet::App->try_to_require($view_class) ) {
        Template::Declare->init( roots => [$view_class, 'Prophet::Server::View'] );

    } else {
        Template::Declare->init( roots => ['Prophet::Server::View'] );
    }
}

override handle_request => sub {
    my ( $self, $cgi ) = validate_pos( @_, { isa => 'Prophet::Server' }, { isa => 'CGI' } );
    $self->cgi($cgi);

     my $dispatcher_class = ref($self->app_handle) . "::Server::Dispatcher";
     if (!$self->app_handle->try_to_require($dispatcher_class)) {
         $dispatcher_class = "Prophet::Server::Dispatcher";
     }
 
 
     my $d =$dispatcher_class->new( server => $self );


    $d->run( $cgi->request_method . "/" . $cgi->path_info, $d )
        || $self->_send_404;

};

sub update_record_prop {
    my $self = shift;
    my $type = $1;
    my $uuid = $2;
    my $prop = $3;

    my $record = $self->load_record( type => $type, uuid => $uuid );
    return $self->_send_404 unless ($record);
    $record->set_props(
        props => { $prop => ( $self->cgi->param('value') || undef ) } );
    return $self->_send_redirect( to => "/records/$type/$uuid/$prop" );
}

sub update_record {
    my $self   = shift;
    my $type   = $1;
    my $uuid   = $2;
    my $record = $self->load_record( type => $type, uuid => $uuid );

    return $self->_send_404 unless ($record);

    my $ret = $record->set_props(
        props => { map { $_ => $self->cgi->param($_) } $self->cgi->param() } );
    $self->_send_redirect( to => "/records/$type/$uuid.json" );
}

sub create_record {
    my $self   = shift;
    my $type   = $1;
    my $record = $self->load_record( type => $type );
    my $uuid   = $record->create(
        props => { map { $_ => $self->cgi->param($_) } $self->cgi->param() } );
    return $self->_send_redirect( to => "/records/$type/$uuid.json" );
}

sub get_record_prop {
    my $self   = shift;
    my $type   = $1;
    my $uuid   = $2;
    my $prop   = $3;
    my $record = $self->load_record( type => $type, uuid => $uuid );
    return $self->_send_404 unless ($record);
    if ( my $val = $record->prop($prop) ) {
        return $self->send_content(
            content_type => 'text/plain',
            content      => $val
        );
    } else {
        return $self->_send_404();
    }
}

sub get_record {
    my $self   = shift;
    my $type   = $1;
    my $uuid   = $2;
    my $record = $self->load_record( type => $type, uuid => $uuid );
    return $self->_send_404 unless ($record);
    return $self->send_content(
        encode_as => 'json',
        content   => $record->get_props
    );
}

sub get_record_list {
    my $self = shift;
    my $type = $1;
    require Prophet::Collection;
    my $col = Prophet::Collection->new(
        handle => $self->handle,
        type   => $type
    );
    $col->matching( sub {1} );
    warn "Query language not implemented yet.";
    return $self->send_content(
        encode_as => 'json',
        content   => {
            map { $_->uuid => "/records/$type/" . $_->uuid . ".json" } @$col
            }

    );
}

sub get_record_types {
    my $self = shift;
        $self->send_content(
            encode_as => 'json',
            content   => $self->handle->list_types
        );
    }


sub serve_replica {
    my $self = shift;

        my $repo_file = $1;
        return undef unless $self->handle->can('read_file');
        my $content = $self->handle->read_file($repo_file);
        return unless defined $content && length($content);
        return $self->send_content(
            content_type => 'application/x-prophet',
            content      => $content
        );
    }

sub show_template {
    my $self = shift;
    my $p    = $1;
    if ( Template::Declare->has_template($p) ) {
        Prophet::Server::View->app_handle( $self->app_handle );
        my $content = Template::Declare->show($p);
        return $self->send_content(
            content_type => 'text/html',
            content      => $content,
        );
    }
    return undef;
}

sub load_record {
    my $self = shift;
    my %args = validate( @_, { type => 1, uuid => 0 } );
    require Prophet::Record;
    my $record
        = Prophet::Record->new( handle => $self->handle, type => $args{type} );
    if ( $args{'uuid'} ) {
        return undef
            unless (
            $self->handle->record_exists(
                type => $args{'type'},
                uuid => $args{'uuid'}
            )
            );
        $record->load( uuid => $args{uuid} );
    }
    return $record;
}

sub send_content {
    my $self = shift;
    my %args
        = validate( @_, { content => 1, content_type => 0, encode_as => 0 } );

    if ( $args{'encode_as'} && $args{'encode_as'} eq 'json' ) {
        $args{'content_type'} = 'text/x-json';
        $args{'content'}      = to_json( $args{'content'} );
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
