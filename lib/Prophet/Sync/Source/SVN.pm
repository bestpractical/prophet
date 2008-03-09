use warnings;
use strict;

package Prophet::Sync::Source::SVN;
use base qw/Prophet::Sync::Source/;
use Params::Validate qw(:all);

use SVN::Core;
use SVN::Ra;
use SVK;
use SVK::Config;
use SVN::Delta;

use Prophet::Handle;
use Prophet::Sync::Source::SVN::ReplayEditor;
use Prophet::ChangeSet;

__PACKAGE__->mk_accessors(qw/url ra prophet_handle/);

sub new {
    my $self = shift->SUPER::new(@_);
    $self->setup();
    return $self;
}

sub setup {
    my $self = shift;
    my ( $baton, $ref ) = SVN::Core::auth_open_helper( SVK::Config->get_auth_providers );
    my $config = SVK::Config->svnconfig;
    $self->ra( SVN::Ra->new( url => $self->url, config => $config, auth => $baton ));

    if ( $self->url =~ /^file:\/\/(.*)$/ ) {
        $self->prophet_handle( Prophet::Handle->new( { repository => $1, db_root => '_prophet' }));
    }

}

sub uuid {
    my $self = shift;
    return $self->ra->get_uuid;
}

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
            original_source_uuid => $revprops->{original_source_uuid},
            original_sequence_no => $revprops->{original_sequence_no},

        }
    );

    # add each node's changes to the changeset
    for my $path ( keys %{ $entry->{'paths'} } ) {
        if ( $path =~ qr|^(.+)/(.*?)/(.*?)$| ) {
            my ( $prefix, $type, $record ) = ( $1, $2, $3 );
            my $change = Prophet::Change->new(
                {   node_type   => $type,
                    node_uuid   => $record,
                    change_type => $entry->{'paths'}->{$path}->{'fs'}
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
            warn "Discarding change to a non-record: $path";
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


sub has_seen_changeset {
    my $self = shift;
    my ($changeset) = validate_pos( @_, { isa => "Prophet::ChangeSet" } );

    my $last_changeset_from_source
        = $self->last_changeset_from_source( $changeset->original_source_uuid || $changeset->source_uuid );

    # if the source's sequence # is >= the changeset's sequence #, we can safely skip it
    return 1 if ( $last_changeset_from_source >= $changeset->sequence_no );
}




sub changeset_will_conflict {
    my $self = shift;
    my ($changeset) = validate_pos( @_, { isa => "Prophet::ChangeSet" } );

    return 1 if ( keys %{$self->conflicts_from_changeset($changeset)});
    return undef;

}

sub conflicts_from_changeset{
    my $self = shift;
    my ($changeset) = validate_pos( @_, { isa => "Prophet::ChangeSet" } );

    my $conflict = Prophet::Conflict->new();

    # XXX TODO
    die "Right here, we need to actually walk through all the changes and generate 
    
    - a ConflictingChange if there are any conflicts in the change
    - for each conflictingchange, we need to create a conflicting change property for each and every property that conflicts


    for my $change ( $changeset->changes ) {
        return 1 if $self->change_will_conflict($change);
    }

    return 0;
}



sub change_will_conflict {
    my $self = shift;
    my ($change) = validate_pos( @_, { isa => "Prophet::Change" } );

    my $current_state = $self->prophet_handle->get_node_props( uuid => $change->node_uuid, type => $change->node_type );

    # It's ok to delete a node that exists
    return 0 if ( $change->change_type eq 'delete' && keys %$current_state );

    # It's ok to create a node that doesn't exist
    return 0 if ( $change->change_type eq 'add_file' && !keys %$current_state );
    return 0 if ( $change->change_type eq 'add_dir'  && !keys %$current_state );

    for my $propchange ( $change->prop_changes ) {
        # skip properties added by the change
        next if ( !defined $current_state->{ $propchange->name } && !defined $propchange->old_value );

        # If either the old version didn't have a value or the delta didn't have a value, then we
        # know there's a conflict
        # Ditto if they don't agree
        return 1
            if (       !exists $current_state->{ $propchange->name }
                    || !defined $propchange->old_value
                    || ( $current_state->{ $propchange->name } ne $propchange->old_value ) );
    }

    return 0;

}

sub integrate_changeset {
    my $self = shift;

    if (there's a conflict ) {
        figure out our conflict resolution
        generate a nullification change
        # IMPORTANT: these should be an atomic unit. dying here would be poor.
        # BUT WE WANT THEM AS THREEDIFFERENT SVN REVS
            integrate the nullification change
            integrate the original change
            integrate the conflict resolution change

    } else {
        $self->prophet_handle->integrate_changeset(@_);

    }
}


# XXX TODO this is hacky as hell and violates abstraction barriers in the name of doing things over the RA

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
