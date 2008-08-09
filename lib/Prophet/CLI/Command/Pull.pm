package Prophet::CLI::Command::Pull;
use Moose;
extends 'Prophet::CLI::Command::Merge';

override run => sub {
    my $self = shift;
    my @from;

    $self->set_arg( db_uuid => $self->handle->db_uuid ) 
        unless ($self->arg('db_uuid'));

    my %previous_sources = $self->_read_cached_upstream_replicas;
    push @from, $self->arg('from')
        if ($self->arg('from') && !$previous_sources{$self->arg('from')});
    push @from, keys %previous_sources if $self->has_arg('all');

    my @bonjour_replicas = $self->find_bonjour_replicas;

    die "Please specify a --from, --local or --all.\n"
        unless ( $self->has_arg('from')
        || $self->has_arg('local')
        || $self->has_arg('all') );

    $self->set_arg( to => $self->cli->app_handle->default_replica_type
            . ":file://"
            . $self->handle->fs_root );

    for my $from ( @from, @bonjour_replicas ) {
        print "Pulling from $from\n";
        #if ( $self->has_arg('all') || $self->has_arg('local') );
        $self->set_arg( from => $from );
        super();
    }

    if ( $self->arg('from') && !exists $previous_sources{$self->arg('from')} ) {
        $previous_sources{$self->arg('from')} = 1;
        $self->_write_cached_upstream_replicas(%previous_sources);
    }
};

=head2 find_bonjour_replicas

Probes the local network for bonjour replicas if the local arg is specified.

Returns a list of found replica URIs.

=cut

sub find_bonjour_replicas {
    my $self = shift;
    my @bonjour_replicas;
    if ( $self->has_arg('local') ) {
        Prophet::App->try_to_require('Net::Bonjour');
        if ( Prophet::App->already_required('Net::Bonjour') ) {
            print "Probing for local database replicas with Bonjour\n";
            my $res = Net::Bonjour->new('prophet');
            $res->discover;
            foreach my $entry ( $res->entries ) {
                if ( $entry->name eq $self->arg('db_uuid') ) {
                    print "Found a database replica on " . $entry->hostname."\n";
                    my $uri = URI->new();
                    $uri->scheme( 'http' );
                    $uri->host($entry->hostname);
                    $uri->port( $entry->port );
                    $uri->path('replica/');
                    push @bonjour_replicas,  $uri->canonical.""; #scalarize
                }
            }
        }

    }
    return @bonjour_replicas;
}

=head2 _read_cached_upstream_replicas

Returns a hash containing url => 1 pairs, where the URLs are the replicas that
have been previously pulled from.

=cut

sub _read_cached_upstream_replicas {
    my $self = shift;
    return map { $_ => 1 } $self->handle->_read_cached_upstream_replicas;
}

=head2 _write_cached_upstream_replicas %replicas

Writes the replica URLs given in C<keys %replicas> to the current Prophet
repository's upstream replica cache (these replicas will be pulled from when a
user specifies --all).

=cut

sub _write_cached_upstream_replicas {
    my $self  = shift;
    my %repos = @_;
    return $self->handle->_write_cached_upstream_replicas(keys %repos);
}

__PACKAGE__->meta->make_immutable;
no Moose;



1;

