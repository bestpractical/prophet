package Prophet::CLI::Command::Clone;
use Moose;
extends 'Prophet::CLI::Command::Merge';

sub run {
    my $self = shift;

    $self->set_arg( 'to' => $self->app_handle->handle->url() );

    my $source = Prophet::Replica->new(
        url       => $self->arg('from'),
        app_handle => $self->app_handle,
    );
    my $target = Prophet::Replica->new(
        url       => $self->arg('to'),
        app_handle => $self->app_handle,
    );

    if ( $target->replica_exists ) {
        die "The target replica already exists."; 
    }

    if (!$target->can_initialize ) {
        die "The replica path you specified isn't writable";
    }

    my %init_args;
    unless ($source->isa('Prophet::ForeignReplica')) {
        %init_args = (
            db_uuid    => $source->db_uuid,
            resdb_uuid => $source->resolution_db_handle->db_uuid,
        );
    }
    $target->initialize(%init_args);

    $target->_write_cached_upstream_replicas($self->arg('from'));
    $self->SUPER::run();
};

__PACKAGE__->meta->make_immutable;
no Moose;

1;
