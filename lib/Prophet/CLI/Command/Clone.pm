package Prophet::CLI::Command::Clone;
use Any::Moose;
extends 'Prophet::CLI::Command::Merge';

sub usage_msg {
    my $self = shift;
    my $cmd = $self->cli->get_script_name;

    return <<"END_USAGE";
usage: ${cmd}clone --from <url>
END_USAGE
}

sub run {
    my $self = shift;

    $self->print_usage if $self->has_arg('h');

    $self->validate_args();

    $self->set_arg( 'to' => $self->app_handle->handle->url() );

    my $source = Prophet::Replica->get_handle(
        url        => $self->arg('from'),
        app_handle => $self->app_handle,
    );
    my $target = Prophet::Replica->get_handle(
        url        => $self->arg('to'),
        app_handle => $self->app_handle,
    );

    if ( $target->replica_exists ) {
        die "The target replica already exists.\n";
    }

    if ( !$target->can_initialize ) {
        die "The target replica path you specified can't be created.\n";
    }

    my %init_args;
    if ( $source->isa('Prophet::ForeignReplica') ) {
        $target->after_initialize( sub { shift->app_handle->set_db_defaults } );
    } else {
        %init_args = (
            db_uuid    => $source->db_uuid,
            resdb_uuid => $source->resolution_db_handle->db_uuid,
        );
    }

    unless ($source->replica_exists) {
        die "The source replica '@{[$source->url]}' doesn't exist or is unreadable.\n";
    }

    $target->initialize(%init_args);

    # create new config section for this replica
    my $from = $self->arg('from');
    $self->app_handle->config->group_set(
        $self->app_handle->config->replica_config_file,
        [ {
            key => 'replica.'.$from.'.url',
            value => $self->arg('from'),
        },
        {   key => 'replica.'.$from.'.uuid',
            value => $target->uuid,
        },
        ]
    );

    if ( $source->can('database_settings') ) {
        my $remote_db_settings = $source->database_settings;
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



__PACKAGE__->meta->make_immutable;
no Any::Moose;

1;
