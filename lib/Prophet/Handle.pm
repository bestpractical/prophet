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

=head2 integrate_changeset L<Prophet::ChangeSet>

Given a L<Prophet::ChangeSet>, integrates each and every change within that changeset into the handle's replica.

This routine also records that we've seen this changeset (and hence everything before it) from both the peer who sent it to us AND the replica who originally created it.


=cut

sub integrate_changeset {
    my $self      = shift;
    my $changeset = shift;

    $self->begin_edit();
    $self->record_changeset($changeset);
    $self->record_changeset_integration($changeset);
    $self->commit_edit();
}

sub record_resolutions {
    my $self       = shift;
    my $changeset  = shift;
    my $res_handle = shift;

    return unless $changeset->changes;

    $self->begin_edit();
    $self->record_changeset($changeset);
    $res_handle->record_resolution($_) for $changeset->changes;
    $self->commit_edit();
}

=head2 record_resolution

Called ONLY on local resolution creation. (Synced resolutions are just synced as records)

=cut

sub record_resolution {
    my ( $self, $change ) = @_;

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

sub record_changeset {
    my $self      = shift;
    my $changeset = shift;

    eval {

        my $inside_edit = $self->current_edit ? 1 : 0;
        $self->begin_edit() unless ($inside_edit);
        $self->_integrate_change($_) for ( $changeset->changes );
        $self->_cleanup_integrated_changeset($changeset);

        $self->commit_edit() unless ($inside_edit);
    };
    die($@) if ($@);
}

sub _integrate_change {
    my $self   = shift;
    my $change = shift;

    my %new_props = map { $_->name => $_->new_value } $change->prop_changes;

    if ( $change->change_type eq 'add_file' ) {
        $self->create_node(
            type  => $change->node_type,
            uuid  => $change->node_uuid,
            props => \%new_props
        );
    } elsif ( $change->change_type eq 'add_dir' ) {
    } elsif ( $change->change_type eq 'update_file' ) {
        $self->set_node_props(
            type  => $change->node_type,
            uuid  => $change->node_uuid,
            props => \%new_props
        );
    } elsif ( $change->change_type eq 'delete' ) {
        $self->delete_node(
            type => $change->node_type,
            uuid => $change->node_uuid
        );
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

1;
