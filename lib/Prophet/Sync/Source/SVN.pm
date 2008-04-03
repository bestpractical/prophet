use warnings;
use strict;

package Prophet::Sync::Source::SVN;
use base qw/Prophet::Sync::Source/;
use Params::Validate qw(:all);
use UNIVERSAL::require;

use SVN::Core;
use SVN::Ra;
use SVN::Delta;

use Prophet::Handle;
use Prophet::Sync::Source::SVN::ReplayEditor;
use Prophet::Sync::Source::SVN::Util;
use Prophet::ChangeSet;
use Prophet::Conflict;

__PACKAGE__->mk_accessors(qw/url ra prophet_handle ressource is_resdb pool/);

our $DEBUG = $Prophet::Handle::DEBUG;

=head2 setup

Open a connection to the SVN source identified by C<$self->url>.

XXX TODO, make the _prophet/ directory in the replica configurable

=cut

sub _get_ra {
    my $self = shift;
    my ( $baton, $ref ) = SVN::Core::auth_open_helper( Prophet::Sync::Source::SVN::Util->get_auth_providers );
    my $config = Prophet::Sync::Source::SVN::Util->svnconfig;
    return SVN::Ra->new( url => $self->url, config => $config, auth => $baton, pool => $self->pool ) ;
}

sub setup {
    my $self = shift;
    my $pool   = SVN::Pool->new;

    $self->pool($pool);

    $self->ra( $self->_get_ra );
    if ( $self->url =~ /^file:\/\/(.*)$/ ) {
        $self->prophet_handle( Prophet::Handle->new( { repository => $1 } ) );
    }
    if ( $self->url =~ m/_res$/ ) {

        # XXX: should probably just point to self
        return;
    }

    my $res_url = $self->url;
    $res_url =~ s/(\_res|)$/_res/;
    $self->ressource( __PACKAGE__->new( { url => $res_url, is_resdb => 1 } ) );
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
    my %args = validate( @_, { after => 1 } );
    my @results;

    my $first_rev = ( $args{'after'} + 1 ) || 1;

    # XXX TODO we should  be using a svn get_log call here rather than simple iteration
    # clkao explains that this won't deal cleanly with cases where there are revision "holes"
    for my $rev ( $first_rev .. $self->ra->get_latest_revnum ) {
        my $editor = Prophet::Sync::Source::SVN::ReplayEditor->new( _debug => 0 );
        $editor->ra( $self->_get_ra );
        my $pool = SVN::Pool->new_default;

        # This horrible hack is here because I have no idea how to pass custom variables into the editor
        $Prophet::Sync::Source::SVN::ReplayEditor::CURRENT_REMOTE_REVNO = $rev;
        $self->ra->replay( $rev, 0, 1, $editor );
        push @results, $self->_recode_changeset( $editor->dump_deltas, $self->ra->rev_proplist($rev) );

    }

    return \@results;
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
    my $last = $self->last_changeset_from_source( $changeset->original_source_uuid );

    # if the source's sequence # is >= the changeset's sequence #, we can safely skip it
    return 1 if ( $last >= $changeset->original_sequence_no );
    return undef;
}

=head2 changeset_will_conflict Prophet::ChangeSet

Returns true if any change that's part of this changeset won't apply cleanly to the head of the current replica

=cut

sub changeset_will_conflict {
    my $self = shift;
    my ($changeset) = validate_pos( @_, { isa => "Prophet::ChangeSet" } );

    return 1 if ( $self->conflicts_from_changeset($changeset) );

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

    my $conflict = Prophet::Conflict->new( { changeset => $changeset, prophet_handle => $self->prophet_handle } );

    $conflict->analyze_changeset();

    return undef unless @{ $conflict->conflicting_changes };

    return $conflict;

}

=head2 integrate_changeset L<Prophet::ChangeSet>

If there are conflicts, generate a nullification change, figure out a conflict resolution and apply the nullification, original change and resolution all at once (as three separate changes).

If there are no conflicts, just apply the change.

=cut

sub integrate_changeset {
    my $self = shift;
    my %args = validate(
        @_,
        {   changeset         => { isa      => 'Prophet::ChangeSet' },
            resolver          => { optional => 1 },
            resolver_class    => { optional => 1 },
            resdb             => { optional => 1 },
            conflict_callback => { optional => 1 }
        }
    );

    my $changeset = $args{'changeset'};

    # when we start to integrate a changeset, we need to do a bit of housekeeping
    # We never want to merge in:
    # merge tickets that describe merges from the local node

    # When we integrate changes, sometimes we will get handed changes we already know about.
    #   - changes from local
    #   - changes from some other party we've merged from
    #   - merge tickets for the same
    # we'll want to skip or remove those changesets

    return if $changeset->original_source_uuid eq $self->prophet_handle->uuid;

    $self->remove_redundant_data($changeset);    #Things we have already seen

    return if ( $changeset->is_empty or $changeset->is_nullification );

    if ( my $conflict = $self->conflicts_from_changeset($changeset) ) {
        $args{conflict_callback}->($conflict) if $args{'conflict_callback'};
        $conflict->resolvers( [ sub { $args{resolver}->(@_) } ] ) if $args{resolver};
        if ( $args{resolver_class} ) {
            $args{resolver_class}->require || die $@;
            $conflict->resolvers( [ sub { $args{resolver_class}->run(@_); } ] )

        }
        my $resolutions = $conflict->generate_resolution( $args{resdb} );

        #figure out our conflict resolution

     # IMPORTANT: these should be an atomic unit. dying here would be poor.  BUT WE WANT THEM AS THREEDIFFERENT SVN REVS
     # integrate the nullification change
        $self->prophet_handle->record_changeset( $conflict->nullification_changeset );

        # integrate the original change
        $self->prophet_handle->integrate_changeset($changeset);

        # integrate the conflict resolution change
        $self->prophet_handle->record_resolutions( $conflict->resolution_changeset,
            $self->ressource ? $self->ressource->prophet_handle : $self->prophet_handle );
    } else {
        $self->prophet_handle->integrate_changeset($changeset);

    }
}

sub remove_redundant_data {
    my ( $self, $changeset ) = @_;

    # XXX: encapsulation
    $changeset->{changes} = [
        grep { $self->is_resdb || $_->node_type ne '_prophet_resolution' } grep {
            !( $_->node_type eq $Prophet::Handle::MERGETICKET_METATYPE && $_->node_uuid eq $self->prophet_handle->uuid )
            } $changeset->changes
    ];
}

=head2 last_changeset_from_source $SOURCE_UUID

Returns the last changeset id seen from the source identified by $SOURCE_UUID

=cut

sub last_changeset_from_source {
    my $self = shift;
    my ($source) = validate_pos( @_, { type => SCALAR } );
    my ( $stream, $pool );

    my $filename = join( "/", $self->prophet_handle->db_root, $Prophet::Handle::MERGETICKET_METATYPE, $source );
    my ( $rev_fetched, $props )
        = eval { $self->ra->get_file( $filename, $self->ra->get_latest_revnum, $stream, $pool ); };

    # XXX TODO this is hacky as hell and violates abstraction barriers in the name of doing things over the RA
    # because we want to be able to sync to a remote replica someday.

    return ( $props->{'last-changeset'} || 0 );

}

1;
