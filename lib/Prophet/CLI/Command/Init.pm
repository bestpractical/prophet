package Prophet::CLI::Command::Init;
use Any::Moose;
extends 'Prophet::CLI::Command';

sub usage_msg {
    my $self = shift;
    my $cmd = $self->cli->get_script_name;
    my $env_var = uc $cmd . '_REPO';
    $env_var =~ s/ //;

    return <<"END_USAGE";
usage: ${cmd}init
END_USAGE
}

sub run {
    my $self = shift;

    $self->print_usage if $self->has_arg('h');

    if ($self->app_handle->handle->replica_exists) {
        die "Your Prophet database already exists.\n";
    }

    $self->app_handle->handle->after_initialize( sub { shift->app_handle->set_db_defaults } );
    $self->app_handle->handle->initialize;
    print "Initialized your new Prophet database.\n";

    # create new config section for this replica
    my $url = $self->app_handle->handle->url;
    $self->app_handle->config->set(
        key => 'replica.'.$url.'.uuid',
        value => $self->app_handle->handle->uuid,
        filename => $self->app_handle->config->replica_config_file,
    );
}


__PACKAGE__->meta->make_immutable;
no Any::Moose;

1;

