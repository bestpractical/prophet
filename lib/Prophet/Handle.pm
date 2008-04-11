use warnings;
use strict;

package Prophet::Handle;
use base 'Class::Accessor';
use Params::Validate;
use Data::Dumper;
use Data::UUID;

our $DEBUG = 0;

__PACKAGE__->mk_accessors(qw/db_uuid/);

=head2 new { repository => $FILESYSTEM_PATH}
 
Create a new subversion filesystem backend repository handle. If the repository don't exist, create it.

=cut

sub new {
    my $class = shift;
    use Prophet::Handle::SVN;
    return Prophet::Handle::SVN->new(@_);
}

=head2 record_resolutions Prophet::ChangeSet, (Prophet::Handle, a resolution database handle)

Given a resolution changeset and a resolution database handle,
record all the resolution changesets as well as resolution records
in the content-addressed-store.

Called ONLY on local resolution creation. (Synced resolutions are just synced as records)

=cut

sub record_resolutions {
    my $self       = shift;
    my ($changeset, $res_handle) = validate_pos(@_, { isa => 'Prophet::ChangeSet'}, { isa => 'Prophet::Handle'});

    return unless $changeset->changes;

    $self->begin_edit();
    $self->record_changeset($changeset);
    $res_handle->record_resolution($_) for $changeset->changes;
    $self->commit_edit();
}

=head2 record_resolution Prophet::Change
 
Called ONLY on local resolution creation. (Synced resolutions are just synced as records)

=cut

sub record_resolution {
    my $self      = shift;
    my ($change) = validate_pos(@_, { isa => 'Prophet::Change'});

    return 1 if $self->node_exists(
        uuid => $self->uuid,
        type => '_prophet_resolution-' . $change->resolution_cas
    );

    $self->create_node(
        uuid  => $self->uuid,
        type  => '_prophet_resolution-' . $change->resolution_cas,
        props => {
            _meta => $change->change_type,
            map { $_->name => $_->new_value } $change->prop_changes
        }
    );
}


=head1 Routines dealing with integrating changesets into a replica


=head2 integrate_changeset L<Prophet::ChangeSet>

Given a L<Prophet::ChangeSet>, integrates each and every change within that changeset into the handle's replica.

This routine also records that we've seen this changeset (and hence everything before it) from both the peer who sent it to us AND the replica who originally created it.


=cut

sub integrate_changeset {
    my $self      = shift;
    my ($changeset) = validate_pos(@_, { isa => 'Prophet::ChangeSet'});

    $self->begin_edit();
    $self->record_changeset($changeset);
    $self->record_changeset_integration($changeset);
    $self->commit_edit();
}

=head2 record_changeset Prophet::ChangeSet

Inside an edit (transaction), integrate all changes in this transaction
and then call the _post_process_integrated_changeset() hook

=cut

sub record_changeset {
    my $self      = shift;
    my ($changeset) = validate_pos(@_, { isa => 'Prophet::ChangeSet'});
    eval {
        my $inside_edit = $self->current_edit ? 1 : 0;
        $self->begin_edit() unless ($inside_edit);
        $self->_integrate_change($_) for ( $changeset->changes );
        $self->_post_process_integrated_changeset($changeset);
        $self->commit_edit() unless ($inside_edit);
    };
    die($@) if ($@);
}

sub _integrate_change {
    my $self   = shift;
    my ($change) = validate_pos(@_, { isa => 'Prophet::Change'});

    my %new_props = map { $_->name => $_->new_value } $change->prop_changes;
    if ( $change->change_type eq 'add_file' ) {
        $self->create_node( type  => $change->node_type, uuid  => $change->node_uuid, props => \%new_props);
    } elsif ( $change->change_type eq 'add_dir' ) {
    } elsif ( $change->change_type eq 'update_file' ) {
        $self->set_node_props( type  => $change->node_type, uuid  => $change->node_uuid, props => \%new_props);
    } elsif ( $change->change_type eq 'delete' ) {
        $self->delete_node( type => $change->node_type, uuid => $change->node_uuid);
    } else {
        Carp::confess( " I have never heard of the change type: " . $change->change_type );
    }

}

our $MERGETICKET_METATYPE = '_merge_tickets';

=head2 record_changeset_integration L<Prophet::ChangeSet>

This routine records the immediately upstream and original source
uuid and sequence numbers for this changeset. Prophet uses this
data to make sane choices about later replay and merge operations


=cut

sub record_changeset_integration {
    my $self = shift;
    my ($changeset) = validate_pos( @_, { isa => 'Prophet::ChangeSet' } );

    # Record a merge ticket for the changeset's "original" source
    $self->_record_merge_ticket( $changeset->original_source_uuid, $changeset->original_sequence_no );

}

sub _record_merge_ticket {
    my $self = shift;
    my ( $source_uuid, $sequence_no ) = validate_pos( @_, 1, 1 );
    return $self->_record_metadata_for( $MERGETICKET_METATYPE, $source_uuid, 'last-changeset', $sequence_no );
}






=head1 metadata storage routines 

=cut 


=head2 metadata_storage $RECORD_TYPE, $PROPERTY_NAME

Returns a function which takes a UUID and an optional value to get (or set) metadata rows in a metadata table.
We use this to record things like merge tickets


=cut

sub metadata_storage {
    my $self = shift;
    my ( $type, $prop_name ) = validate_pos( @_, 1, 1 );
    return sub {
        my $uuid = shift;
        if (@_) {
            return $self->_record_metadata_for( $type, $uuid, $prop_name, @_ );
        }
        return $self->_retrieve_metadata_for( $type, $uuid, $prop_name );

    };
}

sub _retrieve_metadata_for {
    my $self = shift;
    my ( $name, $source_uuid, $prop_name ) = validate_pos( @_, 1, 1, 1 );

    my $entry = Prophet::Record->new( handle => $self, type => $name );
    $entry->load( uuid => $source_uuid );
    return eval { $entry->prop($prop_name) };

}

sub _record_metadata_for {
    my $self = shift;
    my ( $name, $source_uuid, $prop_name, $content ) = validate_pos( @_, 1, 1, 1, 1 );

    my $props = eval { $self->get_node_props( uuid => $source_uuid, type => $name ) };

    # XXX: do set-prop when exists, and just create new node with all props is probably better
    unless ( $props->{$prop_name} ) {
        eval { $self->create_node( uuid => $source_uuid, type => $name, props => {} ) };
    }

    $self->set_node_props(
        uuid  => $source_uuid,
        type  => $name,
        props => { $prop_name => $content }
    );
}





=head1 DATA STORE API

=head1 The following functions need to be implemented by any Prophet backing store.

=head2 uuid

Returns this replica's UUID

=head2 create_node { type => $TYPE, uuid => $uuid, props => { key-value pairs }}

Create a new record of type C<$type> with uuid C<$uuid>  within the current replica.

Sets the record's properties to the key-value hash passed in as the C<props> argument.

If called from within an edit, it uses the current edit. Otherwise it manufactures and finalizes one of its own.



=head2 delete_node {uuid => $uuid, type => $type }

Deletes the node C<$uuid> of type C<$type> from the current replica. 

Manufactures its own new edit if C<$self->current_edit> is undefined.

=head2 set_node_props { uuid => $uuid, type => $type, props => {hash of kv pairs }}


Updates the record of type C<$type> with uuid C<$uuid> to set each property defined by the props hash. It does NOT alter any property not defined by the props hash.

Manufactures its own current edit if none exists.


=head2 get_node_props {uuid => $uuid, type => $type, root => $root }

Returns a hashref of all properties for the record of type $type with uuid C<$uuid>.

'root' is an optional argument which you can use to pass in an alternate historical version of the replica to inspect.  Code to look at the immediately previous version of a record might look like:

    $handle->get_node_props(
        type => $record->type,
        uuid => $record->uuid,
        root => $self->repo_handle->fs->revision_root( $self->repo_handle->fs->youngest_rev - 1 )
    );

=head2 node_exists {uuid => $uuid, type => $type, root => $root }

Returns true if the node in question exists. False otherwise


=head2 enumerate_nodes { type => $type }

Returns a reference to a list of all the records of type $type

=head2 enumerate_nodes

Returns a reference to a list of all the known types in your Prophet database


=head2 type_exists { type => $type }

Returns true if we have any nodes of type C<$type>



=cut





=head2 The following functions need to be implemented by any _writable_ prophet backing store

=cut



=head2 The following optional routines are provided for you to override with backing-store specific behaviour


=head3 _post_process_integrated_changeset Prophet::ChangeSet

Called after the replica has integrated a new changeset but before closing the current transaction/edit.

The SVN backend, for example, uses this to record author metadata about this changeset.

=cut


sub _post_process_integrated_changeset {
    return 1;
}


1;
