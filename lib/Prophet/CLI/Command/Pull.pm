package Prophet::CLI::Command::Pull;
use Moose;
extends 'Prophet::CLI::Command::Merge';

sub run {

    my $self         = shift;
    my $other        = shift @ARGV;
    my $source_other = Prophet::Replica->new( { url => $other } );
    $self->app_handle->handle->import_resolutions_from_remote_replica(
        from => $source_other );

    $self->_do_merge( $source_other, $self->app_handle->handle );

}

__PACKAGE__->meta->make_immutable;
no Moose;

1;

