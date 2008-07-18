package Prophet::CLI::Command::Pull;
use Moose;
extends 'Prophet::CLI::Command::Merge';

override run => sub {
    my $self = shift;

    die "Please specify a --from.\n" if !$self->has_arg('from');

    $self->set_arg(to => $self->cli->app_handle->default_replica_type.":file://"
.$self->cli->app_handle->handle->fs_root);

    super();
};

__PACKAGE__->meta->make_immutable;
no Moose;

1;

