package Prophet::CLI::Command::Init;
use Any::Moose;
extends 'Prophet::CLI::Command';

sub run {
    my $self = shift;

    if ($self->app_handle->handle->replica_exists) {
        print "Your Prophet database already exists.\n";
        return;
    }

    $self->app_handle->handle->after_initialize( sub { shift->app_handle->set_db_defaults } );
    $self->app_handle->handle->initialize;
    print "Initialized your new Prophet database.\n";

    # create new config section for this replica
    $self->app_handle->config->set(
        key => 'replica.'.$self->app_handle->handle->url.'.uuid',
        value => $self->app_handle->handle->uuid,
        filename => $self->app_handle->config->replica_config_file,
    );
}


__PACKAGE__->meta->make_immutable;
no Any::Moose;

1;

