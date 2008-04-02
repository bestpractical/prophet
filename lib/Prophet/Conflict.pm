
use warnings;
use strict;

package Prophet::Conflict;
use Params::Validate;
use base qw/Class::Accessor/;
use Prophet::ConflictingPropChange;
use Prophet::ConflictingChange;

__PACKAGE__->mk_accessors(qw/prophet_handle resolvers changeset nullification_changeset resolution_changeset autoresolved/);

=head2 analyze_changeset Prophet::ChangeSet

Take a look at a changeset. if there are any conflicts, populate
the L<conflicting_changes> array on this object with a set of
L<Prophet::ConflictingChange> objects.

=cut

sub analyze_changeset {
    my $self = shift;
    #my ($changeset) = validate_pos( @_, { isa => 'Prophet::ChangeSet' } );

    $self->generate_changeset_conflicts();
    return unless (@{$self->conflicting_changes});

    $self->generate_nullification_changeset;
    
    return 1;
}

sub _resolution_failed {

    return sub { die "conflict not resolved.\n" };
}

sub resolution_from_resdb {
    my ($self, $resdb, $conflict) = @_;
    # XXX: turn this into an explicit load?
    $resdb->matching( sub { $_[0]->uuid eq $conflict->cas_key });
    my $answer = $resdb->as_array_ref->[0] or return;

    my $resolution = Prophet::Change->new_from_conflict($conflict);
    for my $prop_conflict ( @{ $conflict->prop_conflicts } ) {
        $resolution->add_prop_change(
            name => $prop_conflict->name,
            old  => $prop_conflict->source_old_value,
            new  => $answer->prop( $prop_conflict->name ),
        );
    }
    return $resolution;
}

sub generate_resolution {
    my $self = shift;
    my $resdb = shift;
    my @resolvers = (
        sub { $self->attempt_automatic_conflict_resolution(@_) },
        $resdb ? sub { $self->resolution_from_resdb( $resdb, @_ ) } : (),
        @{ $self->resolvers || [] },
        $self->_resolution_failed
    );

    my $resolutions = Prophet::ChangeSet->new( { is_resolution => 1 } );
    for my $conflict ( @{ $self->conflicting_changes } ) {
        for (@resolvers) {
            if (my $resolution = $_->($conflict)) {
                $resolutions->add_change(change => $resolution) if $resolution->prop_changes;
                last;
            }
        }
    }

    $self->resolution_changeset($resolutions);
    return 1;
}

=head2 attempt_automatic_conflict_resolution

Given a L<Prophet::Conflict> which can not be cleanly applied to a
replica, it is sometimes possible to automatically determine a sane
resolution to the conflict.

=over

=item When the new-state of the conflicting change matches the
previous head of the replica.

=item When someone else has previously done the resolution and we
have a copy of that hanging aroun

** This bit seems hard

=back


In those cases, this routine will generate a L<Prophet::ChangeSet> which resolves 
as many conflicts as possible.

It will then update $self->conflicting_changes to mark which
L<Prophet::ConflictingChange>s and L<Prophet::ConflictingPropChanges>
have been automatically resolved.


=cut


sub attempt_automatic_conflict_resolution {
    my $self = shift;
    my ($conflicting_change) = validate_pos(@_, { isa => 'Prophet::ConflictingChange'});
  # for everything from the changeset that is the same as the old value of the target replica
    # we can skip applying 
    return 0 if $conflicting_change->file_op_conflict;

    my $resolution = Prophet::Change->new_from_conflict( $conflicting_change );

    for my $prop_change ( @{$conflicting_change->prop_conflicts} ) {
        return 0 unless $prop_change->target_value eq $prop_change->source_new_value
    }

    $self->autoresolved(1);

    return $resolution;






}


=head2 generate_changeset_conflicts 

Given a changeset, populates $self->conflicting_changes with all the conflicts that applying that changeset to the target replica would result in.

=cut


sub generate_changeset_conflicts {
    my $self = shift;
    for my $change ( $self->changeset->changes ) {
        if ( my $change_conflicts = $self->_generate_change_conflicts($change) ) {
            push @{ $self->conflicting_changes }, $change_conflicts;
        }
    }
}


=head2 _generate_change_conflicts Prophet::Change

Given a change, generates a set of Prophet::ConflictingChange entries.

=cut

sub _generate_change_conflicts {
    my $self = shift;
    my ($change) = validate_pos( @_, { isa => "Prophet::Change" } );
    my $file_op_conflict = '';
    
    my $file_exists = $self->prophet_handle->node_exists(uuid => $change->node_uuid, type => $change->node_type);
    
    # It's ok to delete a node that exists
    if ( $change->change_type eq 'delete' && !$file_exists ) {
        $file_op_conflict = "delete_missing_file";
    } elsif ( $change->change_type eq 'update' && !$file_exists) {
        $file_op_conflict = "update_missing_file";
    } elsif ( $change->change_type eq 'add_file' && $file_exists) {
        $file_op_conflict = "create_existing_file";
    } elsif ( $change->change_type eq 'add_dir' && $file_exists) {
        # XXX TODO: this isn't right
        $file_op_conflict = "create_existing_dir";
    }

    



    my $change_conflict = Prophet::ConflictingChange->new(
        {   node_type          => $change->node_type,
            node_uuid          => $change->node_uuid,
            target_node_exists => $file_exists,
            change_type        => $change->change_type,
            file_op_conflict   => $file_op_conflict
        }
    );

    if ($file_exists) {
        my $current_state = $self->prophet_handle->get_node_props( uuid => $change->node_uuid, type => $change->node_type );

        push @{ $change_conflict->prop_conflicts }, $self->_generate_prop_change_conflicts( $change, $current_state );
    }
    
     return ( @{ $change_conflict->prop_conflicts } || $file_op_conflict ) ? $change_conflict : undef;
}


=head2 _generate_prop_change_conflicts Prophet::Change %hash_of_current_properties

Given a change and the current state of a node, returns an array of Prophet::ConflictingPropChange objects describing conflicts which would occur if the change were applied


=cut

sub _generate_prop_change_conflicts {
    my $self          = shift;
    my $change        = shift;
    my $current_state = shift;
    my @prop_conflicts;
    for my $prop_change ( $change->prop_changes ) {

        # skip properties added by the change
        next if ( !defined $current_state->{ $prop_change->name } && !defined $prop_change->old_value );

       # If either the old version didn't have a value or the delta didn't have a value, then we know there's a conflict
        my $s = {
            name             => $prop_change->name,
            source_old_value => $prop_change->old_value,
            target_value => $current_state->{ $prop_change->name },
            source_new_value => $prop_change->new_value
        };

        if (   !exists $current_state->{ $prop_change->name }
            || !defined $prop_change->old_value
            || ( $current_state->{ $prop_change->name } ne $prop_change->old_value ) )
        {
            push @prop_conflicts, Prophet::ConflictingPropChange->new($s);
        }

    }
    return @prop_conflicts;
}

=head2 conflicting_changes 

Returns a referencew to an array of conflicting changes for this conflict


=cut

sub conflicting_changes {
    my $self = shift;
    $self->{'conflicting_changes'} ||= [];
    return $self->{'conflicting_changes'};
}


=head2 generate_nullification_changeset

In order to record a changeset which might not apply cleanly to the
current state of a replica, Prophet generates a I<nullification
changeset>. That is, a changeset which sets the state of the replica
back to what it needs to be in order to apply the new changeset.

This routine computes a new L<Prophet::ChangeSet> which contains
everything needed to nullify the conflicting state of the replica.

=cut

sub generate_nullification_changeset {
    my $self = shift;
    my $nullification = Prophet::ChangeSet->new( {is_nullification => 1});

    for my $conflict ( @{ $self->conflicting_changes } ) {
        my $nullify_conflict = Prophet::Change->new( { node_type => $conflict->node_type, node_uuid => $conflict->node_uuid });

        if ( $conflict->file_op_conflict eq "delete_missing_file" ) {
            $nullify_conflict->change_type('create_file');
        } elsif ( $conflict->file_op_conflict eq "update_missing_file" ) {
            $nullify_conflict->change_type('create_file');
        } elsif ( $conflict->file_op_conflict eq "create_existing_file" ) {
            $nullify_conflict->change_type('delete');
        } elsif ( $conflict->file_op_conflict ) {
            die "We don't know how to deal with a conflict of type " . $conflict->file_op_conflict;
        } else {
            $nullify_conflict->change_type('update_file');
        }
        
        

        # now that we've sorted out all the file-level conflicts, we need to get properties in order
        for my $prop_conflict ( @{ $conflict->prop_conflicts } ) {
            $nullify_conflict->add_prop_change(
                name => $prop_conflict->name,
                old  => $prop_conflict->target_value,
                new  => $prop_conflict->source_old_value
            );
        }
        $nullification->add_change( change => $nullify_conflict );
    }

    $self->nullification_changeset($nullification);
}

1;

