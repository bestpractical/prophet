use warnings;
use strict;

package Prophet::Replica::HTTP;
use base qw/Prophet::Replica/;
use Params::Validate qw(:all);
use LWP::Simple 'get';

use Prophet::Handle;
use Prophet::ChangeSet;
use Prophet::Conflict;

__PACKAGE__->mk_accessors(qw/url db_uuid/);

our $DEBUG = $Prophet::Handle::DEBUG;

=head2 setup

Open a connection to the SVN source identified by C<$self->url>.

=cut

sub setup {
    my $self = shift;

    $self->{url} =~ s{/$}{};
    my ($db_uuid) = $self->url =~ m{^.*/(.*?)$};
    $self->db_uuid($db_uuid);

    unless ($self->is_resdb) {
        $self->ressource( __PACKAGE__->new( { url => $self->{url}.'/resolutions', is_resdb => 1 } ) );
    }
}

=head2 uuid

Return the replica SVN repository's UUID

=cut

sub uuid {
    my $self = shift;
    return get($self->url.'/replica-uuid');
}

=head2 fetch_changesets { after => SEQUENCE_NO } 

Fetch all changesets from the source. 

Returns a reference to an array of L<Prophet::ChangeSet/> objects.


=cut

# each record is : local-replica-seq-no : original-uuid : original-seq-no : cas key
#                       4                    16              4                 20

use constant CHG_RECORD_SIZE =>  ( 4 + 16 + 4 +20 );

sub fetch_changesets {
    my $self = shift;
    my %args = validate( @_, { after => 1 } );
    my @results;

    my $first_rev = ( $args{'after'} + 1 ) || 1;

    my $latest = get($self->url.'/latest');

    my $chgidx = get($self->url.'/changesets.idx');

    for my $rev ( $first_rev .. $latest ) {
        my ($seq, $orig_uuid, $orig_seq, $key)
            = unpack('Na16Na20', substr( $chgidx, ($rev-1)*CHG_RECORD_SIZE, CHG_RECORD_SIZE ) );
        $orig_uuid = Data::UUID->new->to_string( $orig_uuid );
$ug->to_string( $uuid );
        my $changeset = Prophet::ChangeSet->new({ source_uuid => $self->uuid, sequence_no => $seq
                                                  original_source_uuid => $orig_uuid, original_sequence_no => $orig_seq,
                                                });
        # XXX: deserialize the changeset content from the cas with $key
    }

    return \@results;
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