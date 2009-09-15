package Prophet::Resolver::IdenticalChanges;
use Any::Moose;
use Params::Validate qw(:all);
use Prophet::Change;
extends 'Prophet::Resolver';

=head1 METHODS

=head2 attempt_automatic_conflict_resolution

Given a L<Prophet::Conflict> which can not be cleanly applied to a
replica, it is sometimes possible to automatically determine a sane
resolution to the conflict.

=over

=item *

When the new-state of the conflicting change matches the
previous head of the replica.

=item *

When someone else has previously done the resolution and we
have a copy of that hanging around.

=back

In those cases, this routine will generate a L<Prophet::ChangeSet>
which resolves as many conflicts as possible.

It will then update the conclicting changes to mark which
L<Prophet::ConflictingChange>s and L<Prophet::ConflictingPropChanges>
have been automatically resolved.

=cut

sub run {
    my $self = shift;
    my ( $conflicting_change, $conflict, $resdb )
        = validate_pos( @_, { isa => 'Prophet::ConflictingChange' }, { isa => 'Prophet::Conflict' }, 0 );

    # for everything from the changeset that is the same as the old value of the target replica
    # we can skip applying
    return 0 if $conflicting_change->file_op_conflict;

    my $resolution = Prophet::Change->new_from_conflict($conflicting_change);

    for my $prop_change ( @{ $conflicting_change->prop_conflicts } ) {
        next if ((!defined $prop_change->target_value || $prop_change->target_value  eq '')
                
                && ( !defined $prop_change->source_new_value || $prop_change->source_new_value eq ''));
        next if (defined  $prop_change->target_value 
        and defined $prop_change->source_new_value
            and ( $prop_change->target_value eq $prop_change->source_new_value));
        return 0; 
    }

    $conflict->autoresolved(1);

    return $resolution;

}

__PACKAGE__->meta->make_immutable;
no Any::Moose;

1;
