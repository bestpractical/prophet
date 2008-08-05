package Prophet::CLI::Command::Pull;
use Moose;
extends 'Prophet::CLI::Command::Merge';

override run => sub {
    my $self  = shift;
    my @from;

    my $from = $self->arg('from');
    push @from, $from if $from;

    my %replicas = $self->_read_cached_upstream_replicas;
    push @from, keys %replicas
        if $self->has_arg('all');

    die "Please specify a --from, or --all.\n" if @from == 0;

    $self->set_arg(to => $self->cli->app_handle->default_replica_type.":file://".$self->cli->app_handle->handle->fs_root);
    $self->set_arg(db_uuid => $self->app_handle->handle->db_uuid);

    for my $from (@from) {
            print "Pulling from $from\n" if $self->has_arg('all');
            $self->set_arg(from => $from);
            super();
    }

    if ($from && !exists $replicas{$from}) {
        $replicas{$from} = 1;
        $self->_write_cached_upstream_replicas(%replicas);
    }
};

sub _read_cached_upstream_replicas {
    my $self = shift;
    return map { $_ => 1 } $self->cli->app_handle->resdb_handle->_read_cached_upstream_replicas;
}

sub _write_cached_upstream_replicas {
    my $self  = shift;
    my %repos = @_;
    return $self->cli->app_handle->resdb_handle->_write_cached_upstream_replicas(keys %repos);
}

__PACKAGE__->meta->make_immutable;
no Moose;



1;

