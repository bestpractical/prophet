use warnings;
use strict;

package Prophet::Sync::Source::RT;
use base qw/Prophet::Sync::Source/;
use Params::Validate qw(:all);
use UNIVERSAL::require;
use RT::Client::REST;

use Prophet::Handle;
use Prophet::ChangeSet;
use Prophet::Conflict;

__PACKAGE__->mk_accessors(qw/url prophet_handle ressource is_resdb rt/);

our $DEBUG = $Prophet::Handle::DEBUG;

=head2 setup

Open a connection to the SVN source identified by C<$self->url>.

XXX TODO, make the _prophet/ directory in the replica configurable

=cut

sub setup {
    my $self = shift;
    $self->rt(RT::Client::REST->new(server => 'http://rt3.fsck.com' ));
    $self->rt->login(username => 'guest', password => 'guest');
}

sub fetch_resolutions { warn 'no resdb'}

=head2 uuid

Return the replica SVN repository's UUID

=cut

sub uuid {
    my $self = shift;
    return 1234;
    return Carp::cluck "need a uuid";
}

=head2 fetch_changesets { after => SEQUENCE_NO } 

Fetch all changesets from the source. 

Returns a reference to an array of L<Prophet::ChangeSet/> objects.


=cut

sub fetch_changesets {
    my $self = shift;
    my %args = validate( @_, { after => 1 } );

    my $first_rev = ( $args{'after'} + 1 ) || 1;

    my @txns;
    my %tix;
    for my $id ($self->_find_matching_tickets) {
        $tix{$id} = $self->rt->show(type => 'ticket', id => $id);
        push @txns, $self->_find_matching_txns($id);
    }


    my @results = map { $self->_recode_changeset($_) } sort { $a->id <=> $b->id } @txns;
    return \@results;
}


sub _find_matching_tickets {
    my $self = shift;
    
             # Find all stalled tickets
             my @tix = $self->rt->search(
               type => 'ticket',
               query => "Status = 'stalled'",
             );
return @tix;

}

sub _find_matching_transactions {
    my $self = shift;
    my $ticket = shift;
    my @txns;
    for my $txn ($self->rt->get_transaction_ids (parent_id => $ticket ) ) {
           push @txns, get_transaction (parent_id => $ticket, id => $txn, type => 'ticket');
    }
    return @txns;
}


sub _recode_changeset {
    my $self      = shift;
    my $entry     = shift;
    my $revprops  = shift;
    my $changeset = Prophet::ChangeSet->new(
        {   sequence_no          => $entry->{'revision'},
            source_uuid          => $self->uuid,
            original_source_uuid => $revprops->{'prophet:original-source'} || $self->uuid,
            original_sequence_no => $revprops->{'prophet:original-sequence-no'} || $entry->{'revision'},
            is_nullification     => ( ( $revprops->{'prophet:special-type'} || '' ) eq 'nullification' ) ? 1 : undef,
            is_resolution        => ( ( $revprops->{'prophet:special-type'} || '' ) eq 'resolution' ) ? 1 : undef,

        }
    );

    # add each node's changes to the changeset
    for my $path ( keys %{ $entry->{'paths'} } ) {
        if ( $path =~ qr|^(.+)/(.*?)/(.*?)$| ) {
            my ( $prefix, $type, $record ) = ( $1, $2, $3 );
            my $change = Prophet::Change->new(
                {   node_type   => $type,
                    node_uuid   => $record,
                    change_type => $entry->{'paths'}->{$path}->{fs_operation}
                }
            );
            for my $name ( keys %{ $entry->{'paths'}->{$path}->{prop_deltas} } ) {
                $change->add_prop_change(
                    name => $name,
                    old  => $entry->{paths}->{$path}->{prop_deltas}->{$name}->{'old'},
                    new  => $entry->{paths}->{$path}->{prop_deltas}->{$name}->{'new'},
                );
            }

            $changeset->add_change( change => $change );

        } else {
            warn "Discarding change to a non-record: $path" if $DEBUG;
        }

    }
    return $changeset;
}


=head2 last_changeset_from_source $SOURCE_UUID

Returns the last changeset id seen from the source identified by $SOURCE_UUID

=cut

sub last_changeset_from_source {
    my $self = shift;
    my ($source) = validate_pos( @_, { type => SCALAR } );
    my ( $stream, $pool );

    my $filename = join( "/", $self->prophet_handle->db_root, $Prophet::Handle::MERGETICKET_METATYPE, $source );
    my ( $rev_fetched, $props ) = eval { $self->ra->get_file( $filename, $self->ra->get_latest_revnum, $stream, $pool ); };
    return ( $props->{'last-changeset'} || 0 );

}


1;
