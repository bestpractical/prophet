package Prophet::CLI::Command::Clone;
use Any::Moose;
extends 'Prophet::CLI::Command::Merge';

sub run {
    my $self = shift;

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
    $target->initialize(%init_args);

    $self->app_handle->config->set(
        _sources =>
            { $self->arg('from') => $self->arg('from') }
    );
    $self->app_handle->config->save;

    $self->SUPER::run();
}

sub validate_args {
    my $self = shift;
    die "Please specify a --from.\n"
        unless $self->has_arg('from');
}

# When we clone from another replica, we ALWAYS want to take their way forward,
# even when there's an insane, impossible conflict
#
sub merge_resolver { 'Prophet::Resolver::AlwaysTarget'}



__PACKAGE__->meta->make_immutable;
no Any::Moose;

1;
