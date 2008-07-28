package Prophet::CLI::Command::Push;
use Moose;
extends 'Prophet::CLI::Command::Merge';

before run => sub {
    my $self = shift;

    die "Please specify a --to.\n" if !$self->has_arg('to');

    $self->set_arg(from => $self->app_handle->default_replica_type.":file://".$self->app_handle->handle->fs_root);
    $self->set_arg(db_uuid => $self->app_handle->handle->db_uuid);
};

__PACKAGE__->meta->make_immutable;
no Moose;

1;

