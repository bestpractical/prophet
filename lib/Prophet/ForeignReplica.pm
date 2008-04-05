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

use Data::UUID 'NameSpace_DNS';

sub uuid_for_url {
    my ( $self, $url ) = @_;
    return Data::UUID->new->create_from_name_str( NameSpace_DNS, $url );
}

1;
