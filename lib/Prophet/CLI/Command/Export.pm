package Prophet::CLI::Command::Export;
use Moose;
extends 'Prophet::CLI::Command';

sub run {
    my $self = shift;

    $self->app_handle->handle->export_to( path => $self->arg('path') );
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;

