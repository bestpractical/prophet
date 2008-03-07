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

sub uuid {
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
    my $self  = shift;
    my $entry = shift;

    my $changeset = Prophet::ChangeSet->new(
        {   sequence_no => $entry->{'revision'},
            source_uuid => $self->uuid
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
sub accepts_changesets {
    my $self = shift;
    return 1 if $self->prophet_handle;
    return undef;
}


sub has_seen_changeset { 
    my $self = shift;
    my ($changeset) =  validate_pos(@_, {isa => "Prophet::ChangeSet"});

    # find the last changeset for the source
    my $last_changeset_from_source = $self->last_changeset_from_source($changeset->source_uuid);
    
    # if the source's sequence # is >= the changeset's sequence #, we can safely skip it
  
    warn "the liast changeset I saw from ".$changeset->source_uuid . " was $last_changeset_from_source";
    warn "my changeset is ".$changeset->sequence_no;
    if ($last_changeset_from_source >= $changeset->sequence_no) {
        return 1;
    }

    
    



}

sub changeset_will_conflict { 
    my $self = shift;
    my ($changeset) =  validate_pos(@_, {isa => "Prophet::ChangeSet"} );

    warn "Checking ".$changeset->sequence_no."@".$changeset->source_uuid ." for conflicts";

    for my $change ($changeset->changes) {
        return 1 if $self->change_will_conflict($change);
    }

    return 0;
}

sub change_will_conflict {
    my $self = shift;
    my ($change) =  validate_pos(@_, {isa => "Prophet::Change"} );

    $change->change_type;
    
    my $current_state = $self->prophet_handle->get_node_props(uuid => $change->node_uuid, type => $change->node_type);

     # It's ok to delete a node that exists
     return 0 if ($change->change_type eq 'delete' && keys %$current_state) ;
     
     # It's ok to create a node that doesn't exist
     return 0 if ($change->change_type eq 'add_file' && ! keys %$current_state) ;
     return 0 if ($change->change_type eq 'add_dir' && ! keys %$current_state) ;

    for my $propchange ( $change->prop_changes ) {
        next if ( !defined $current_state->{ $propchange->name } && !defined $propchange->old_value );
        return 1 if 
        (      !exists $current_state->{ $propchange->name }
            || !defined $propchange->old_value
            || ( $current_state->{ $propchange->name } ne $propchange->old_value ) );
    }

    return 0;

}




sub integrate_changeset {
    my $self      = shift;
    my $changeset = shift;

    # open up a change handle locally
    warn "Applying Changeset " . $changeset->sequence_no;

    $self->prophet_handle->begin_edit();

    for my $change ( $changeset->changes ) {
        warn "\tApplying a change";
        warn "\t" . $change->change_type;

        my %new_props = map { $_->name => $_->new_value } $change->prop_changes;

        if ( $change->change_type eq 'add_file' ) {
            warn "\tAdded a file - " . $change->node_type, $change->node_uuid;
            $self->prophet_handle->create_node(
                type  => $change->node_type,
                uuid  => $change->node_uuid,
                props => \%new_props
            );
        } elsif ( $change->change_type eq 'add_dir' ) {
            warn "\tAdded a dir - " . $change->node_type, $change->node_uuid;
        } elsif ( $change->change_type eq 'update_file' ) {
            warn "\tUpdated a file - " . $change->node_type, $change->node_uuid;
            $self->prophet_handle->set_node_props(
                type  => $change->node_type,
                uuid  => $change->node_uuid,
                props => \%new_props
            );
        } elsif ( $change->change_type eq 'delete' ) {
            warn "\tDeleted file - " . $change->node_type, $change->node_uuid;
            $self->prophet_handle->delete_node(
                type => $change->node_type,
                uuid => $change->node_uuid
            );
        }

    }

    $self->prophet_handle->commit_edit();

    # finalize the local change
}




# XXX TODO this is hacky as hell and violates abstraction barriers in the name of doing things over the RA

sub last_changeset_from_source {
    my $self = shift;
    # XXX TODO should htis be an object rather than a uuid?
    my ($source) = validate_pos(@_, {type => SCALAR } );
    my ( $stream, $pool );

    # XXX HACK
    my $filename = join( "/", "_prophet", $Prophet::Handle::MERGETICKET_METATYPE, $source );
    warn "Looking up $filename";
    my ( $rev_fetched, $props ) = eval {
        $self->ra->get_file( $filename, $self->ra->get_latest_revnum, $stream, $pool );
    };

    return ( $props->{'last-changeset'} ||0 );

}

sub record_changeset_integration {
    my $self = shift;

    return undef unless ( $self->accepts_changesets );
    my ($changeset) = validate_pos(@_, { isa => 'Prophet::ChangeSet'});

    $self->prophet_handle->record_changeset_integration($changeset);

}

1;
