use warnings;
use strict;


package Prophet::ForeignReplica;
use base qw/Prophet::Replica/;
use Params::Validate qw(:all);
use App::Cache;

=head1 NAME

=head1 DESCRIPTION

This abstract baseclass implements the helpers you need to be able to easily sync a prophet replica with a "second class citizen" replica which can't exactly reconstruct changesets, doesn't use uuids to track records and so on.

=cut

sub conflicts_from_changeset { return; }
sub accepts_changesets       {1}
sub import_resolutions_from_remote_source { warn 'no resdb'; return }



sub record_changeset {
    my $self = shift;
    my ($changeset) = validate_pos( @_, { isa => 'Prophet::ChangeSet' } );
    for my $change ( $changeset->changes ) {
        my $result = $self->_integrate_change( $change, $changeset );
    }

}



my $SOURCE_CACHE = App::Cache->new( { ttl => 60 * 60 } );    # la la la
# "Remote bookkeeping merge tickets."
# recording a merge ticket locally on behalf of the source ($self)
# Prophet::Record type '_remote_merge_tickets'? 

sub record_changeset_integration {
    my ( $self, $source_uuid, $source_seq ) = @_;
    return $SOURCE_CACHE->set( $self->uuid . '-' . $source_uuid => $source_seq );
}

=head2 last_changeset_from_source $SOURCE_UUID

Returns the last changeset id seen from the source identified by $SOURCE_UUID

=cut

sub last_changeset_from_source {
    my $self = shift;
    my ($source_uuid) = validate_pos( @_, { type => SCALAR } );
    return $SOURCE_CACHE->get( $self->uuid . '-' . $source_uuid ) || 0;
}




sub record_integration_changeset {
    warn "record_integration_changeset should be renamed to 'record_original_change";
    my ( $self, $changeset ) = @_;
    $self->record_changeset($changeset);

    # does the merge ticket recording & _source_metadata (book keeping for what txns in rt we just created)

    $self->record_changeset_integration( $changeset->original_source_uuid, $changeset->original_sequence_no );
}




use Data::UUID 'NameSpace_DNS';

sub uuid_for_url {
    my ( $self, $url ) = @_;
    return Data::UUID->new->create_from_name_str( NameSpace_DNS, $url );
}

1;
