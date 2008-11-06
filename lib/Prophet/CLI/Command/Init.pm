package Prophet::CLI::Command::Init;
use Moose;
extends 'Prophet::CLI::Command';

sub run {
    my $self = shift;

    $self->app_handle->handle->after_initialize( sub { shift->app_handle->set_db_defaults } );
    $self->app_handle->handle->initialize;
    $self->app_handle->log("Initialized");

}


__PACKAGE__->meta->make_immutable;
no Moose;

1;

