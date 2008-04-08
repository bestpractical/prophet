use warnings;
use strict;

package Prophet::Replica::HTTP;
use base qw/Prophet::Replica/;
use Params::Validate qw(:all);
use LWP::Simple ();

use Prophet::Handle;
use Prophet::ChangeSet;
use Prophet::Conflict;

__PACKAGE__->mk_accessors(qw/url db_uuid _uuid/);

our $DEBUG = $Prophet::Handle::DEBUG;

=head2 setup

Open a connection to the SVN source identified by C<$self->url>.

=cut

sub setup {
    my $self = shift;

    $self->{url} =~ s/^prophet://;    # url-based constructor in ::replica should do better
    $self->{url} =~ s{/$}{};
    my ($db_uuid) = $self->url =~ m{^.*/(.*?)$};
    $self->db_uuid($db_uuid);

    unless ( $self->is_resdb ) {

        #        $self->ressource( __PACKAGE__->new( { url => $self->{url}.'/resolutions', is_resdb => 1 } ) );
    }
}

=head2 uuid

Return the replica SVN repository's UUID

=cut

sub uuid {
    my $self = shift;

    $self->_uuid( LWP::Simple::get( $self->url . '/replica-uuid' ) ) unless $self->_uuid;
    return $self->_uuid;
}

=head2 fetch_changesets { after => SEQUENCE_NO } 

Fetch all changesets from the source. 

Returns a reference to an array of L<Prophet::ChangeSet/> objects.


=cut

# each record is : local-replica-seq-no : original-uuid : original-seq-no : cas key
#                       4                    16              4                 20

use constant CHG_RECORD_SIZE => ( 4 + 16 + 4 + 20 );

sub traverse_changesets {
    my $self = shift;
    my %args = validate(
        @_,
        {   after    => 1,
            callback => 1,
        }
    );

    my $first_rev = ( $args{'after'} + 1 ) || 1;

    my $latest = LWP::Simple::get( $self->url . '/latest-sequence-no' );

    my $chgidx = LWP::Simple::get( $self->url . '/changesets.idx' );

    for my $rev ( $first_rev .. $latest ) {
        my ( $seq, $orig_uuid, $orig_seq, $key )
            = unpack( 'Na16NH40', substr( $chgidx, ( $rev - 1 ) * CHG_RECORD_SIZE, CHG_RECORD_SIZE ) );
        $orig_uuid = Data::UUID->new->to_string($orig_uuid);

        # XXX: deserialize the changeset content from the cas with $key
        my $casfile = $self->url . '/cas/changesets/' . substr( $key, 0, 1 ) . '/' . substr( $key, 1, 1 ) . '/' . $key;

        my $content = YAML::Syck::Load( LWP::Simple::get($casfile) );

        my $changeset = Prophet::ChangeSet->new_from_hashref($content);
        $changeset->source_uuid( $self->uuid );
        $changeset->sequence_no($seq);
        $changeset->original_source_uuid($orig_uuid);
        $changeset->original_sequence_no($orig_seq);
        $args{callback}->($changeset);
    }
}

sub record_integration_changeset {
    die 'readonly';
}

sub record_changeset {
    die 'readonly';
}

sub record_resolutions {
    die 'readonly';
}

1;
