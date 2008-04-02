use warnings;
use strict;

package Prophet::PropChange;
use base qw/Class::Accessor/;

__PACKAGE__->mk_accessors(qw/name old_value new_value/);

=head1 NAME

Prophet::PropChange

=head1 DESCRIPTION

This class encapsulates a single property change. 

=head1 METHODS

=head2 name

The name of the property we're talking about.

=head2 old_value

What L</name> changed I<from>.

=head2 new_value

What L</name> changed I<to>.


=cut

1;
