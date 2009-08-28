package Prophet::CLI::Command::Clone;
use Any::Moose;
extends 'Prophet::CLI::Command::Merge';

sub usage_msg {
    my $self = shift;
    my $cmd = $self->cli->get_script_name;

    return <<"END_USAGE";
usage: ${cmd}clone --from <url> | --local
END_USAGE
}

sub run {
    my $self = shift;

    $self->print_usage if $self->has_arg('h');

    if ($self->has_arg('local')) {
        $self->list_bonjour_sources;
        return;
    }

    $self->validate_args();

    $self->set_arg( 'to' => $self->app_handle->handle->url() );

    $self->source( Prophet::Replica->get_handle(
        url       => $self->arg('from'),
        app_handle => $self->app_handle,
    ));

    $self->target( Prophet::Replica->get_handle(
        url       => $self->arg('to'),
        app_handle => $self->app_handle,
    ));

    if ( $self->target->replica_exists ) {
        die "The target replica already exists.\n";
    }

    if ( !$self->target->can_initialize ) {
        die "The target replica path you specified can't be created.\n";
    }

    my %init_args;
    if ( $self->source->isa('Prophet::ForeignReplica') ) {
        $self->target->after_initialize( sub { shift->app_handle->set_db_defaults } );
    } else {
        %init_args = (
            db_uuid    => $self->source->db_uuid,
            resdb_uuid => $self->source->resolution_db_handle->db_uuid,
        );
    }

    unless ($self->source->replica_exists) {
        die "The source replica '@{[$self->source->url]}' doesn't exist or is unreadable.\n";
    }

    $self->target->initialize(%init_args);

    # create new config section for this replica
    my $from = $self->arg('from');
    $self->app_handle->config->group_set(
        $self->app_handle->config->replica_config_file,
        [ {
            key => 'replica.'.$from.'.url',
            value => $self->arg('from'),
        },
        {   key => 'replica.'.$from.'.uuid',
            value => $self->target->uuid,
        },
        ]
    );

    if ( $self->source->can('database_settings') ) {
        my $remote_db_settings = $self->source->database_settings;
        my $default_settings   = $self->app_handle->database_settings;
        for my $name ( keys %$remote_db_settings ) {
            my $uuid = $default_settings->{$name}[0];
            die $name unless $uuid;
            my $s = $self->app_handle->setting( uuid => $uuid );
            $s->set( $remote_db_settings->{$name} );
        }
    }

    $self->SUPER::run();
}

sub validate_args {
    my $self = shift;

    unless ( $self->has_arg('from') ) {
        warn "No --from specified!\n";
        die $self->print_usage;
    }
}

# When we clone from another replica, we ALWAYS want to take their way forward,
# even when there's an insane, impossible conflict
#
sub merge_resolver { 'Prophet::Resolver::AlwaysTarget'}


=head2 list_bonjour_sources

Probes the local network for bonjour replicas if the local arg is specified.

Prints a list of all sources found.

=cut
sub list_bonjour_sources {
    my $self = shift;
    my @bonjour_sources;

    Prophet::App->try_to_require('Net::Bonjour');
    if ( Prophet::App->already_required('Net::Bonjour') ) {
        print "Probing for local sources with Bonjour\n\n";
        my $res = Net::Bonjour->new('prophet');
        $res->discover;
        my $count = 0;
        for my $entry ( $res->entries ) {
                require URI;
                my $uri = URI->new();
                $uri->scheme( 'http' );
                $uri->host($entry->hostname);
                $uri->port( $entry->port );
                $uri->path('replica/');
                print '  * '.$uri->canonical.' - '.$entry->name."\n";
                $count++;
        }

        if ($count) {
            print "\nFound $count source".($count==1? '' : 's')."\n";
        }
        else {
            print "No local sources found.\n";
        }
    }

    return;
}


__PACKAGE__->meta->make_immutable;
no Any::Moose;

1;
