package Prophet::CLI::Command::Pull;
use Moose;
extends 'Prophet::CLI::Command::Merge';

sub run {
    my $self = shift;
    my @from;

    my $previous_sources = $self->app_handle->config->sources;


    my $explicit_from = '';
    
    if ($self->has_arg('from')) {
        $explicit_from = $self->arg('from') ;
        push @from, $explicit_from;
    }

    elsif ($self->has_arg('all')){
        for my $source (values %$previous_sources) {
            my ($url, $uuid ) = split(qr/ \| /,$source,2);
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

sub record_pull_from_source {
    my $self = shift;
    my $source = shift;
    my $from_uuid = shift;
    my $previous_sources = $self->app_handle->config->sources;
    my %sources_by_url = map {
            my $meta = $_;
            my ($url,$uuid);
            ($url, $uuid ) = split(qr/ \| /,$meta,2);
         ($previous_sources->{$meta} => $url )
     } keys %$previous_sources;
    if ( !exists $sources_by_url{$source}) {
        $previous_sources->{$source} = $source ." | ".$from_uuid;
        $self->app_handle->config->set(_sources => $previous_sources );
        $self->app_handle->config->save;
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
no Moose;



1;

