use warnings;
use strict;

package Prophet::Sync::Source::SVN;
use base qw/Class::Accessor/;
use Params::Validate;

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
    my ( $baton, $ref )
        = SVN::Core::auth_open_helper( SVK::Config->get_auth_providers );
    my $config = SVK::Config->svnconfig;
    $self->ra(
        SVN::Ra->new( url => $self->url, config => $config, auth => $baton )
    );

    if ( $self->url =~ /^file:\/\/(.*)$/ ) {
        warn "Connecting to $1";
        $self->prophet_handle(
            Prophet::Handle->new(
                { repository => $1, db_root => '_prophet' }
            )
        );
    }

}

sub unique_id {
    my $self = shift;
    return $self->ra->get_uuid;
}

sub fetch_changesets {
    my $self = shift;
    my @results;
    my $last_editor;
    my $handle_replayed_txn = sub {
        $last_editor = Prophet::Sync::Source::SVN::ReplayEditor->new( _debug => 0 );
        $last_editor->ra( $self->ra );
        return $last_editor;
    };

    for my $rev ( 1 .. $self->ra->get_latest_revnum ) {
        # This horrible hack is here because I have no idea how to pass custom variables into the editor
        $Prophet::Sync::Source::SVN::ReplayEditor::CURRENT_REMOTE_REVNO = $rev;

        $self->ra->replay( $rev, 0, 1, $handle_replayed_txn->() );
        push @results, $self->_recode_changeset( $last_editor->dump_deltas);

    }
    return \@results;
}


sub _recode_changeset {
    my $self = shift;
    my $entry = shift;

        my $changeset = Prophet::ChangeSet->new(
            {   changeset_uuid => $entry->{'revision'}.'@'.$self->unique_id,
                source_uuid => $self->unique_id
            }
        );
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
                    warn "Changing $name for $change";
                    $change->add_prop_change(
                        name => $name,
                        old => $entry->{paths}->{$path}->{prop_deltas}->{$name}->{'old'},
                        new => $entry->{paths}->{$path}->{prop_deltas}->{$name}->{'new'},
                    );
                }

                $changeset->add_change( change => $change );
            } else {
                     warn "Discarding change to a non-record: $path";
            }

        }
        return $changeset;
    }
sub accepts_changesets {
    my $self = shift;
    return 1 if $self->prophet_handle;
    return undef;
}


sub has_seen_changeset { warn "\tneed to implement has_seen_changeset"; return undef;}
sub changeset_will_conflict { warn "\tneed to implement changeset_will_conflict"; return undef }
sub apply_changeset {
    my $self = shift;
    my $changeset = shift;
    # open up a change handle locally
    warn "Applying Changeset ".$changeset->changeset_uuid;

    $self->prophet_handle->begin_edit();

    for my $change ($changeset->changes) {
        warn "\tApplying a change";
        warn "\t".$change->change_type;

        my %new_props = map { $_->name => $_->new_value } $change->prop_changes;

        if ($change->change_type eq 'add_file') {
                warn "\tAdded a file - ".$change->node_type,$change->node_uuid;
                $self->prophet_handle->create_node(type => $change->node_type, uuid => $change->node_uuid, props => \%new_props);
        } elsif ($change->change_type eq 'add_dir') {
                warn "\tAdded a dir - ".$change->node_type,$change->node_uuid;
        } elsif ($change->change_type eq 'update_file') {
                warn "\tUpdated a file - ".$change->node_type,$change->node_uuid;
                $self->prophet_handle->set_node_props(type => $change->node_type, uuid => $change->node_uuid, props => \%new_props);
        } elsif ($change->change_type eq 'delete') {
                warn "\tDeleted file - ".$change->node_type,$change->node_uuid;
                $self->prophet_handle->delete_node(type => $change->node_type, uuid => $change->node_uuid);
        }

    }

    $self->prophet_handle->commit_edit();

    # finalize the local change
}




# XXX TODO this is hacky as hell and violates abstraction barriers in the name of doing things over the RA
sub last_changeset_for_source {
    my $self = shift;
    my %args = validate( @_, { source => 1 } );
    my ( $stream, $pool );

    # XXX HACK
    my $filename = join( "/",
        "_prophet", $Prophet::Handle::MERGETICKET_METATYPE,
        $args{'source'} );
    my ( $rev_fetched, $props ) = eval {
        $self->ra->get_file( $filename, $self->ra->get_latest_revnum,
            $stream, $pool );
    };
    return ( $props->{'last-rev'} );

}

sub record_changeset_for_source {
    my $self = shift;
    return undef unless ( $self->accepts_changesets );
    my %args = validate( @_, { source => 1, changeset => 1 } );
    $self->prophet_handle->record_changeset_for_source(%args);

}

1;
