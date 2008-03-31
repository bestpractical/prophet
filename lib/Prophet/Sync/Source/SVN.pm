use warnings;
use strict;

package Prophet::Sync::Source::SVN;
use base qw/Prophet::Sync::Source/;
use Params::Validate qw(:all);

use SVN::Core;
use SVN::Ra;
use SVN::Delta;

use Prophet::Handle;
use Prophet::Sync::Source::SVN::ReplayEditor;
use Prophet::Sync::Source::SVN::Util;
use Prophet::ChangeSet;
use Prophet::Conflict;

__PACKAGE__->mk_accessors(qw/url ra prophet_handle/);

our $DEBUG = $Prophet::Handle::DEBUG;

=head2 setup

Open a connection to the SVN source identified by C<$self->url>.

XXX TODO, make the _prophet/ directory in the replica configurable

=cut

sub setup {
    my $self = shift;
    my ( $baton, $ref ) = SVN::Core::auth_open_helper( Prophet::Sync::Source::SVN::Util->get_auth_providers );
    my $config = Prophet::Sync::Source::SVN::Util->svnconfig;
    $self->ra( SVN::Ra->new( url => $self->url, config => $config, auth => $baton ));

    if ( $self->url =~ /^file:\/\/(.*)$/ ) {
        $self->prophet_handle( Prophet::Handle->new( { repository => $1, db_root => '_prophet' }));
    }

}

=head2 uuid

Return the replica SVN repository's UUID

=cut

sub uuid {
    my $self = shift;
    return $self->ra->get_uuid;
}

=head2 fetch_changesets { after => SEQUENCE_NO } 

Fetch all changesets from the source. 

Returns a reference to an array of L<Prophet::ChangeSet/> objects.


=cut

sub fetch_changesets {
    my $self = shift;
    my %args = validate( @_, { after => 1});
    my @results;
    my $last_editor;

    my $handle_replayed_txn = sub {
        $last_editor = Prophet::Sync::Source::SVN::ReplayEditor->new( _debug => 0 );
        $last_editor->ra( $self->ra );
        return $last_editor;
    };

    my $first_rev = $args{'after'} || 1;

    # XXX TODO we should  be using a svn get_log call here rather than simple iteration
    # clkao explains that this won't deal cleanly with cases where there are revision "holes"
    for my $rev ( $first_rev .. $self->ra->get_latest_revnum ) {
        # This horrible hack is here because I have no idea how to pass custom variables into the editor
        $Prophet::Sync::Source::SVN::ReplayEditor::CURRENT_REMOTE_REVNO = $rev;
        $self->ra->replay( $rev, 0, 1, $handle_replayed_txn->() );
        push @results, $self->_recode_changeset( $last_editor->dump_deltas, $self->ra->rev_proplist($rev) );

    }
    return \@results;
}


sub _recode_changeset {
    my $self  = shift;
    my $entry = shift;
    my $revprops = shift;

    my $changeset = Prophet::ChangeSet->new(
        {   sequence_no          => $entry->{'revision'},
            source_uuid          => $self->uuid,
            original_source_uuid => $revprops->{'prophet:original-source'} || $self->uuid,
            original_sequence_no => $revprops->{'prophet:original-sequence-no'} || $entry->{'revision'},

        });

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



=head2 accepts_changesets

Returns true if this source is one we know how to write to (and have permission to write to)

Returns false otherwise

=cut

sub accepts_changesets {
    my $self = shift;

    return 1 if $self->prophet_handle;
    return undef;
}


=head2 has_seen_changeset Prophet::ChangeSet

Returns true if we've previously integrated this changeset, even if we originally recieved it from a different peer

=cut


sub has_seen_changeset {
    my $self = shift;
    my ($changeset) = validate_pos( @_, { isa => "Prophet::ChangeSet" } );

    # If the changeset originated locally, we never want it
    return 1 if $changeset->original_source_uuid eq $self->uuid;
    # Otherwise, if the we have a merge ticket from the source, we don't want the changeset
    my $last = $self->last_changeset_from_source( $changeset->original_source_uuid || $changeset->source_uuid );
        
    # if the source's sequence # is >= the changeset's sequence #, we can safely skip it
    return 1 if ( $last >= $changeset->sequence_no );

}


=head2 changeset_will_conflict Prophet::ChangeSet

Returns true if any change that's part of this changeset won't apply cleanly to the head of the current replica

=cut

sub changeset_will_conflict {
    my $self = shift;
    my ($changeset) = validate_pos( @_, { isa => "Prophet::ChangeSet" } );

    return 1 if ( $self->conflicts_from_changeset($changeset));
    
    return undef;

}

=head2 conflicts_from_changeset Prophet::ChangeSet

Returns a L<Prophet::Conflict/> object if the supplied L<Prophet::ChangeSet/>
will generate conflicts if applied to the current replica.

Returns undef if the current changeset wouldn't generate a conflict.

=cut

sub conflicts_from_changeset {
    my $self = shift;
    my ($changeset) = validate_pos( @_, { isa => "Prophet::ChangeSet" } );

    my $conflict = Prophet::Conflict->new({ prophet_handle => $self->prophet_handle});

    $conflict->analyze_changeset($changeset);
    

    return undef unless @{$conflict->conflicting_changes};

    return $conflict;


}

=head2 integrate_changeset L<Prophet::ChangeSet>

If there are conflicts, generate a nullification change, figure out a conflict resolution and apply the nullification, original change and resolution all at once (as three separate changes).

If there are no conflicts, just apply the change.

=cut

sub integrate_changeset {
    my $self = shift;
    my ($changeset) = validate_pos(@_, { isa => 'Prophet::ChangeSet'});

=begin comment

    # when we start to integrate a changeset, we need to do a bit of housekeeping
    # We never want to merge in:
        # merge tickets that describe merges from the local node
        
        
    # When we integrate changes, sometimes we will get handed changes we already know about.
    #   - changes from local
    #   - changes from some other party we've merged from
    #   - merge tickets for the same
    # we'll want to skip or remove those changesets
        
        
=cut        
    return if $changeset->original_source_uuid eq $self->prophet_handle->uuid;
    $self->remove_redundant_data($changeset); #Things we have already seen
    return if ($changeset->is_empty or $changeset->is_nullification);

    if (my $conflict = $self->conflicts_from_changeset($changeset ) ) {
        #figure out our conflict resolution
        # generate a nullification change
        # IMPORTANT: these should be an atomic unit. dying here would be poor.
        # BUT WE WANT THEM AS THREEDIFFERENT SVN REVS
        #integrate the nullification change
        #    integrate the original change
        #    integrate the conflict resolution change

    } else {
        $self->prophet_handle->integrate_changeset(@_);

    }
}

sub remove_redundant_data {
    my ($self, $changeset) = @_;
    # XXX: encapsulation
    $changeset->{changes} = [ grep {
        !($_->node_type eq $Prophet::Handle::MERGETICKET_METATYPE &&
          $_->node_uuid eq $self->prophet_handle->uuid)
    } $changeset->changes ];
}


# XXX TODO this is hacky as hell and violates abstraction barriers in the name of doing things over the RA

=head2 last_changeset_from_source $SOURCE_UUID

Returns the last changeset id seen from the source identified by $SOURCE_UUID

# XXX TODO, we need to move the code from handle here entirely

=cut

sub last_changeset_from_source {
    my $self = shift;
    # XXX TODO should htis be an object rather than a uuid?
    my ($source) = validate_pos(@_, {type => SCALAR } );
    my ( $stream, $pool );

    # XXX HACK
    my $filename = join( "/", "_prophet", $Prophet::Handle::MERGETICKET_METATYPE, $source );
    my ( $rev_fetched, $props ) = eval { $self->ra->get_file( $filename, $self->ra->get_latest_revnum, $stream, $pool ); };

    return ( $props->{'last-changeset'} ||0 );

}


1;
