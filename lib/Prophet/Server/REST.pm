use warnings;
use strict;

package Prophet::Server::REST;
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
    my ($cgi) = validate_pos( @_, { isa => 'CGI' } );
    my $http_status;
    if ( my $sub = $self->can( 'handle_request_' . lc( $cgi->request_method ) ) ) {
        $http_status = $sub->( $self, $cgi );
    }
    unless ($http_status) {
        $self->_send_404;
    }
}

sub handle_request_get {
    my $self = shift;
    my ($cgi) = validate_pos( @_, { isa => 'CGI' } );
    my $p = $cgi->path_info;

    if ( $p =~ m|^/records\.json$| ) {
        $self->_send_content(
            content_type => 'text/x-json',
            content      => to_json( $self->prophet_handle->list_types )
        );

    } elsif ( $p =~ m|^/records/(.*)/(.*)/(.*)| ) {
        my $type   = $1;
        my $uuid   = $2;
        my $prop   = $3;
        my $record = $self->load_record( type => $type, uuid => $uuid );
        return $self->_send_404 unless ($record);
        if ( my $val = $record->prop($prop) ) {
            return $self->_send_content( content_type => 'text/plain', content => $val );
        } else {
            return $self->_send_404();
        }
    }

    elsif ( $p =~ m|^/records/(.*)/(.*).json| ) {
        my $type   = $1;
        my $uuid   = $2;
        my $record = $self->load_record( type => $type, uuid => $uuid );
        return $self->_send_404 unless ($record);
        return $self->_send_content( content_type => 'text/x-json', content => to_json( $record->get_props ) );
    }

    elsif ( $p =~ m|^/records/(.*).json| ) {
        my $type = $1;
        my $col = Prophet::Collection->new( handle => $self->prophet_handle, type => $type );
        $col->matching( sub {1} );
        warn "Todo. query language";
        return $self->_send_content(
            content_type => 'text/x-json',
            content      => to_json( { map { $_->uuid => "/records/$type/" . $_->uuid . ".json" } @$col } )
            )

    }
}

sub handle_request_post {
    my $self = shift;
    my ($cgi) = validate_pos( @_, { isa => 'CGI' } );
    my $p = $cgi->path_info;
    if ( $p =~ m|^/records/(.*)/(.*)/(.*)| ) {
        my $type = $1;
        my $uuid = $2;
        my $prop = $3;

        my $record = $self->load_record( type => $type, uuid => $uuid );
        return $self->_send_404 unless ($record);
        $record->set_props( props => { $prop => ( $cgi->param('value') || undef ) } );
        return $self->_send_redirect( to => "/records/$type/$uuid/$prop" );
    } elsif ( $p =~ m|^/records/(.*)/(.*).json| ) {
        my $type   = $1;
        my $uuid   = $2;
        my $record = $self->load_record( type => $type, uuid => $uuid );

        return $self->_send_404 unless ($record);

        my $ret = $record->set_props( props => { map { $_ => $cgi->param($_) } $cgi->param() } );
        $self->_send_redirect( to => "/records/$type/$uuid.json" );
    } elsif ( $p =~ m|^/records/(.*).json| ) {
        my $type   = $1;
        my $record = $self->load_record( type => $type );
        my $uuid   = $record->create( props => { map { $_ => $cgi->param($_) } $cgi->param() } );
        return $self->_send_redirect( to => "/records/$type/$uuid.json" );
    }
}

sub load_record {
    my $self = shift;
    my %args = validate( @_, { type => 1, uuid => 0 } );

    my $record = Prophet::Record->new( handle => $self->prophet_handle, type => $args{type} );
    if ( $args{'uuid'} ) {
        return undef unless ( $self->prophet_handle->record_exists( type => $args{'type'}, uuid => $args{'uuid'} ) );
        $record->load( uuid => $args{uuid} );
    }
    return $record;
}

sub _send_content {
    my $self = shift;
    my %args = validate( @_, { content => 1, content_type => 1 } );
    print "HTTP/1.0 200 OK\r\n";
    print "Content-Type: " . $args{'content_type'} . "\r\n";
    print "Content-Length: " . length( $args{'content'} ) . "\r\n\r\n";
    print $args{'content'};
    return '200';
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
