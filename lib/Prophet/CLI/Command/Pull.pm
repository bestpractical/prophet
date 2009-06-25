package Prophet::CLI::Command::Pull;
use Any::Moose;
extends 'Prophet::CLI::Command::Merge';

sub ARG_TRANSLATIONS { shift->SUPER::ARG_TRANSLATIONS(),  l => 'local' };

sub run {
    my $self = shift;
    my @from;

    Prophet::CLI->end_pager();

    my %previous_sources_by_name = $self->app_handle->config->sources;

    my $explicit_from = '';

    if ($self->has_arg('from')) {
        # substitute friendly name -> replica url if we can
        $explicit_from
            = exists $previous_sources_by_name{$self->arg('from')}
            ? $previous_sources_by_name{$self->arg('from')}
            : $self->arg('from');
        push @from, $explicit_from;
    }
    elsif ($self->has_arg('all')){
        for my $url (values %previous_sources_by_name) {
            push @from, $url;
        }
    }

    $self->validate_args;
    $self->set_arg( to =>  $self->handle->url );

    for my $from (grep { defined } ( @from, $self->find_bonjour_sources )) {
        print "Pulling from $from\n";
        #if ( $self->has_arg('all') || $self->has_arg('local') );
        $self->set_arg( from => $from );
        $self->SUPER::run();
        if ($self->source->uuid and ($from eq $explicit_from)) {
            $self->record_pull_from_source($explicit_from, $self->source->uuid);
        }
        print "\n";
    }

}

# Create a new [replica] config file section for this replica if we haven't
# pulled from it before.
sub record_pull_from_source {
    my $self = shift;
    my $source = shift;
    my $from_uuid = shift;

    my %previous_sources_by_url
        = $self->app_handle->config->sources( by_url => 1 );

    my $found_prev_replica = $previous_sources_by_url{$source};

    if ( !$found_prev_replica ) {
        $self->app_handle->config->group_set(
            $self->app_handle->config->replica_config_file,
            [
            {
                key => "replica.$source.url",
                value => $source,
            },
            {
                key => "replica.$source.uuid",
                value => $from_uuid,
            },
            ],
        );
    }
}

sub validate_args {
    my $self = shift;
    die "Please specify a --from, --local or --all.\n"
        unless ( $self->has_arg('from')
        || $self->has_arg('local')
        || $self->has_arg('all') );
}

=head2 find_bonjour_sources

Probes the local network for bonjour replicas if the local arg is specified.

Returns a list of found replica URIs.

=cut

sub find_bonjour_sources {
    my $self = shift;
    my @bonjour_sources;

    # We can't pull from bonjour sources if we don't have a db yet
    return undef unless $self->app_handle->handle->replica_exists; 

    my $db_uuid = $self->arg('db_uuid') || $self->app_handle->handle->db_uuid; 

    if ( $self->has_arg('local') ) {
        Prophet::App->try_to_require('Net::Bonjour');
        if ( Prophet::App->already_required('Net::Bonjour') ) {
            print "Probing for local database replicas with Bonjour\n";
            my $res = Net::Bonjour->new('prophet');
            $res->discover;
            for my $entry ( $res->entries ) {
                if ( $entry->name eq $db_uuid ) {
                    print "Found a database replica on " . $entry->hostname."\n";
                    require URI;
                    my $uri = URI->new();
                    $uri->scheme( 'http' );
                    $uri->host($entry->hostname);
                    $uri->port( $entry->port );
                    $uri->path('replica/');
                    push @bonjour_sources,  $uri->canonical.""; #scalarize
                }
            }
        }

    }
    return @bonjour_sources;
}

__PACKAGE__->meta->make_immutable;
no Any::Moose;



1;

