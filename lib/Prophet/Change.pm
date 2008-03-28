use warnings;
use strict;

package Prophet::Change;
use base qw/Class::Accessor/;

use Prophet::PropChange;

use Params::Validate;
__PACKAGE__->mk_accessors(qw/node_type node_uuid change_type/);

=head1 NAME

Prophet::Change

=head1 DESCRIPTION

This class encapsulates a change to a single node in a Prophet replica.

=head1 METHODS

=head2 node_type

The record type for the node.

=head2 node_uuid

The UUID of the node being changed

=head2 change_type

One of create_file, add_dir, update_file, delete
XXX TODO is it create_file or add_file?

=head2 prop_changes

Returns a list of L<Prophet::PropChange/> associated with this Change

=cut


sub prop_changes {
    my $self = shift;
    return @{$self->{prop_changes}};
}


=head2 add_prop_change { new => __, old => ___, name => ___ }

Adds a new L<Prophet::PropChange> to this L<Prophet::Change>.

Takes a C<name>, and the C<old> and C<new> values.

=cut

sub add_prop_change {
    my $self = shift;
    my %args = validate(@_, { name => 1, old => 0, new => 0 } );
    my $change = Prophet::PropChange->new();
    $change->name($args{'name'});
    $change->old_value($args{'old'});
    $change->new_value($args{'new'});

    push @{$self->{prop_changes}}, $change;


}


1;
