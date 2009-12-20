package Prophet::Replica::FS::Backend::LWP;
use Any::Moose;
use Params::Validate qw/validate validate_pos/;
use LWP::UserAgent;

has url => ( is => 'rw', isa => 'Str');

has lwp_useragent => (
    isa => 'LWP::UserAgent',
    is => 'ro',
    lazy => 1,
    default => sub {
        my $ua = LWP::UserAgent->new( timeout => 60, keep_alive => 4, agent => "Prophet/".$Prophet::VERSION);
        return $ua;
    }
);

sub read_file {
	my $self = shift;
    my ($file) = validate_pos( @_, 1 );

        return $self->lwp_get( $self->url . "/" . $file );
}

sub read_file_range {
    my $self = shift;
    my %args = validate( @_, { path => 1, position => 1, length => 1 } );

        # XXX: do range get if possible
        my $content = $self->lwp_get( $self->url . "/" . $args{path} );
        return substr($content, $args{position}, $args{length});

}

sub lwp_get {
    my $self = shift;
    my $url  = shift;

    my $response;
    for ( 1 .. 4 ) {
        $response = $self->lwp_useragent->get($url);
        if ( $response->is_success ) {
            return $response->content;
        }
    }
    warn "Could not fetch " . $url . " - " . $response->status_line . "\n";
    return undef;
}
          

sub write_file {

}

sub append_to_file {

}

sub file_exists {
	my $self = shift;
    my ($file) = validate_pos( @_, 1 );
        return defined $self->read_file($file) ? 1 : 0;
}


sub can_read { 1;

}

sub can_write { 0;

}

1;
