
use warnings;
use strict;
package Prophet::ConflictingPropChange;
use base qw/Class::Accessor/;

__PACKAGE__->mk_accessors(qw/name source_old_value target_value source_new_value/);

=head1 NAME

Prophet::ConflictingPropChange

=head1 DESCRIPTION

Objects of this class describe a case when the a property change can not be cleanly applied to a replica because the old value for the property locally did not match the "begin state" of the change being applied.

=head1 METHODS

=head2 name

The property name for the conflict in question

=head2 source_old_value

The inital (old) state from the change being merged in

=head2 source_new_value

The final (new) state of the property from the change being merged in.

=head2 target_value

The current target-replica value of the property being merged.

=cut

1;
