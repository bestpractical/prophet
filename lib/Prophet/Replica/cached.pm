package Prophet::Replica::cached;
use Any::Moose;

extends 'Prophet::Replica';

use constant scheme   => 'prophet-cache';
use constant cas_root => 'cas';
use constant changeset_cas_dir =>
    File::Spec->catdir( __PACKAGE__->cas_root => 'changesets' );


has fs_root => (
    is      => 'rw',
    lazy    => 1,
    default => sub {
        my $self = shift;
        return $self->app_handle->handle->url =~ m{^file://(.*)$} ? $1.'/remote-replica-cache' : undef;
    },
);

    
has changeset_index => (
    is => 'rw',
    lazy => 1,
    default => sub {
        my $self = shift;
    File::Spec->catdir( $self->fs_root, 'replica', $self->replica_uuid, 'changesets.idx');
        
    }

);    




1;