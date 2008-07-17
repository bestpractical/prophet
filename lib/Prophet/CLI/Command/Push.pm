package Prophet::CLI::Command::Push;
use Moose;
extends 'Prophet::CLI::Command::Merge';

sub run {
    my $self = shift;

    my $source_me    = $self->app_handle->handle;
    my $other        = $self->arg('to');
    my $source_other = Prophet::Replica->new( { url => $other } );
    my $resdb        = $source_me->import_resolutions_from_remote_replica(
        from => $source_other );

    $self->_do_merge( $source_me, $source_other );
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;

