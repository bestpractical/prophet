package Prophet::CLI::Command::Init;
use Moose;
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
}


__PACKAGE__->meta->make_immutable;
no Moose;

1;

