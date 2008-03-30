
use warnings;
use strict;

package Prophet::ConflictingChange;
use Prophet::ConflictingPropChange;

use base qw/Class::Accessor/;

# change_type is one of: add_file add_dir update delete
__PACKAGE__->mk_accessors(qw/node_type node_uuid source_node_exists target_node_exists change_type file_op_conflict/);

=head2 prop_conflicts

Returns a reference to an array of Prophet::ConflictingPropChange objects

=cut

sub prop_conflicts {
    my $self = shift;

    $self->{'prop_conflicts'} ||= [];
    return $self->{prop_conflicts};

}

1;
