package Prophet::CLI::Command::Push;
use Any::Moose;
extends 'Prophet::CLI::Command::Merge';

sub run {
    my $self = shift;

    die "Please specify a --to.\n" if !$self->has_arg('to');

    $self->set_arg(from => $self->app_handle->default_replica_type.":file://".$self->handle->fs_root);
    $self->set_arg(db_uuid => $self->handle->db_uuid);
    $self->SUPER::run(@_);
}

__PACKAGE__->meta->make_immutable;
no Any::Moose;

1;

