use warnings;
use strict;

package Prophet::Conflict;

use base qw/Class::Accessor/;

__PACKAGE__->mk_accessors(qw/prophet_handle   source_change target_change/);

=head2 analyze_changeset Prophet::ChangeSet

Take a look at a changeset. if there are any conflicts, populate the L<conflicting_changes> array on this object with a set of L<Prophet::ConflictingChange> objects.

=cut

sub analyze_changeset {
    my $self = shift;
    my ($changeset) = validate_pos( @_, { isa => 'Prophet::ChangeSet' } );

    # XXX TODO

#    - a ConflictingChange if there are any conflicts in the change
#    - for each conflictingchange, we need to create a conflicting change property for each and every property that conflicts

    for my $change ( $changeset->changes ) {
        if ( my $change_conflicts = $self->generate_change_onflicts($change) ) {
            push @{ $self->{conflicting_changes} }, $change_conflicts;
        }
    }

    return 0;

}

sub generate_change_conflict {
    my $self = shift;
    my ($change) = validate_pos( @_, { isa => "Prophet::Change" } );

    my $current_state = $self->prophet_handle->get_node_props( uuid => $change->node_uuid, type => $change->node_type );

    my $file_op_conflict = '';

    # It's ok to delete a node that exists
    if ( $change->change_type eq 'delete' && !keys %$current_state ) {
        $file_op_conflict = "delete_missing_file";
    } elsif ( $change->change_type eq 'add_file' && keys %$current_state ) {
        $file_op_conflict = "create_existing_file";
    } elsif ( $change->change_type eq 'add_dir' && keys %$current_state ) {
        $file_op_conflict = "create_existing_dir";
    }

    my @prop_conflicts;
    for my $propchange ( $change->prop_changes ) {

        # skip properties added by the change
        next if ( !defined $current_state->{ $propchange->name } && !defined $propchange->old_value );

       # If either the old version didn't have a value or the delta didn't have a value, then we know there's a conflict
        my $s = {
            source_old_value => $propchange->old_value,
            target_old_value => $current_state->{$propchange_name},
            source_new_value => $propchange->new_value
        };

        if (   !exists $current_state->{ $propchange->name }
            || !defined $propchange->old_value
            || ( $current_state->{ $propchange->name } ne $propchange->old_value ) )
        {
            push @prop_conflicts, Prophet::ConflictingPropChange->new($s);

        }

    }

    my $change_conflict = Prophet::ConflictingChange->new(
        {   node_type          => $change->node_type,
            node_uuid          => $change->node_uuid,
            target_node_exists => ( keys %$current_state ? 1 : 0 ),
            change_type        => $change->change_type,
            fileop_conflict    => $fileop_conflict
        }
    );
    push @{ $change_conflict->prop_conflicts }, @prop_conflicts;

    return $change_conflict if ( $#prop_conflicts || $fileop_conflict );
    return undef;
}

=head2 conflicting_changes 

Returns a referencew to an array of conflicting changes for this conflict


=cut

sub conflicting_changes {
    my $self = shift;
    $self->{'conflicting_changes'} ||= ();
    return $self->{'conflicting_changes'};
}

sub generate_nullification_changeset {
    my $self = shift;

    my $nullification = Prophet::ChangeSet->new();
    return $nullification;
}

package Prophet::ConflictingChange;

use base qw/Class::Accessor/;

# change_type is one of: create update delete
__PACKAGE__->mk_accessors(qw/node_type node_uuid source_node_exists target_node_exists change_type fileop_conflict/);

=head2 prop_conflicts

Returns a reference to an array of Prophet::ConflictingPropChange objects

=cut

sub prop_conflicts {
    my $self = shift;

    $self->{'prop_conflicts'} ||= ();
    return $self->{prop_conflicts};

}

package Prophet::ConflictingPropChange;

use base qw/Class::Accessor/;

__PACKAGE__->mk_accessors(qw/source_old_value target_value source_new_value/);

1;
