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

sub record_integration_changeset {
    warn "record_integration_changeset should be renamed to 'record_original_change";
    my ( $self, $changeset ) = @_;
    $self->record_changeset($changeset);

    # XXX: this can now be back in the base class and always record in state_handle sanely
    # does the merge ticket recording & _source_metadata (book keeping for what txns in rt we just created)

    $self->state_handle->begin_edit;
    $self->state_handle->record_changeset_integration($changeset);
    $self->state_handle->commit_edit;

    return;
}




use Data::UUID 'NameSpace_DNS';

sub uuid_for_url {
    my ( $self, $url ) = @_;
    return Data::UUID->new->create_from_name_str( NameSpace_DNS, $url );
}

1;
