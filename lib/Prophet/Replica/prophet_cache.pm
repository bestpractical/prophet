package Prophet::Replica::prophet_cache;
use Any::Moose;

extends 'Prophet::Replica';
with 'Prophet::FilesystemReplica';
use Params::Validate ':all';
use File::Path qw/mkpath/;

has '+db_uuid' => (
    lazy    => 1,
    default => sub { shift->app_handle->handle->db_uuidl() }
);

has uuid => ( is => 'rw');

has _replica_version => (
    is      => 'rw',
    isa     => 'Int',
    lazy    => 1,
    default => sub { shift->_read_file('replica-version') || 0 }
);

has fs_root_parent => (
    is      => 'rw',
    lazy    => 1,
    default => sub {
        my $self = shift;
        return $self->app_handle->handle->url =~ m{^file://(.*)/.*?$} ? $1 : undef;
    },
);


has changeset_cas => (
    is  => 'rw',
    isa => 'Prophet::ContentAddressedStore',
    lazy => 1,
    default => sub {
        my $self = shift;
        Prophet::ContentAddressedStore->new(
            { fs_root => $self->fs_root,
              root    => $self->changeset_cas_dir } );
    },
);

has '+resolution_db_handle' => (
    isa     => 'Prophet::Replica | Undef',
    lazy    => 1,
    default => sub { return shift }
);

use constant userdata_dir    => 'userdata';
use constant local_metadata_dir => 'local_metadata';
use constant scheme   => 'prophet_cache';
use constant cas_root => 'cas';
use constant changeset_cas_dir => File::Spec->catdir( __PACKAGE__->cas_root => 'changesets' );
has fs_root => (
    is      => 'rw',
    lazy    => 1,
    default => sub {
        my $self = shift;
        return $self->app_handle->handle->url =~ m{^file://(.*)$} ? $1.'/remote-replica-cache/' : undef;
    },
);

use constant replica_dir => 'replica';
    
has changeset_index => (
    is => 'rw',
    lazy => 1,
    default => sub {
        my $self = shift;
        File::Spec->catdir($self->replica_dir , $self->uuid, 'changesets.idx');
    }

);    

use constant can_read_records    => 0;
use constant can_read_changesets => 1;
sub can_write_changesets { return ( shift->fs_root ? 1 : 0 ) }
use constant can_write_records    => 0;

=head2 replica_exists

Returns true if the replica already exists / has been initialized.
Returns false otherwise.

=cut

sub replica_exists {
    my $self = shift;
    return $self->_replica_version ? 1 : 0;
}

# XXX should be in a mixin
sub can_initialize {
    my $self = shift;
    if ( $self->fs_root_parent && -w $self->fs_root_parent ) {
        return 1;

    }
    return 0;
}



sub initialize {
    my $self = shift;
    my %args = validate(
        @_,
        {   db_uuid    => 1,
            replica_uuid => 1,
            resdb_uuid => 0,
        }
    );
    if ( !$self->fs_root_parent ) {
        if ( $self->can_write_changesets ) {
            die
                "We can only create local prophet replicas. It looks like you're trying to create "
                . $self->url;
        } else {
            die "Prophet couldn't find a replica at \""
                . $self->fs_root_parent
                . "\"\n\n"
                . "Please check the URL and try again.\n";

        }
    }

    return if $self->replica_exists;
    for (
        $self->cas_root,
        $self->changeset_cas_dir,
        $self->replica_dir,
        File::Spec->catdir($self->replica_dir, $args{'replica_uuid'}),
        $self->userdata_dir
        )
    {
        mkpath( [ File::Spec->catdir( $self->fs_root => $_ ) ] );
    }

    $self->set_db_uuid( $self->app_handle->handle->db_uuid);
    $self->after_initialize->($self);
}



=head2 traverse_changesets { after => SEQUENCE_NO, callback => sub { } } 

Walks through all changesets from $after to $until, calling $callback on each.

If no $until is specified, the latest changeset is assumed.


XXXX THIS SHOULD BE IN FilesystemReplica, but mouse mixins are broken for conflicting method names

=cut

# each record is : local-replica-seq-no : original-uuid : original-seq-no : cas key
#                  4                    16              4                 20


sub traverse_changesets {
    my $self = shift;
    my %args = validate(
        @_,
        {   after           => 1,
            callback        => 1,
            until           => 0,
            reverse         => 0,
            load_changesets => 0
        }
    );

    my $first_rev = ( $args{'after'} + 1 ) || 1;

    my $chgidx = $self->read_changeset_index;
    my $latest = $self->_changeset_index_size(index_file => $chgidx);

      if ( defined $args{until} && $args{until} < $latest) {
    my $latest = $args{until};

    }

    $self->log_debug("Traversing changesets between $first_rev and $latest");
    my @range = ( $first_rev .. $latest );
    @range = reverse @range if $args{reverse};
    for my $rev (@range) {
        $self->log_debug("Fetching changeset $rev");
        if ( $args{load_changesets} ) {
            my $changeset = $self->_get_changeset_index_entry(
                sequence_no => $rev,
                index_file  => $chgidx
            );
            $args{callback}->($changeset);
        } else {
            my $data = $self->_changeset_index_entry(
                sequence_no => $rev,
                index_file  => $chgidx
            );
            $args{callback}->($data);
        }

    }
}




1;
