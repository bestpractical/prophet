use warnings;
use strict;

package Prophet;

our $VERSION = '0.743';

=head1 NAME

Prophet

=head1 DESCRIPTION

Prophet is a distributed database system designed for small to medium
scale social database applications.  Our early targets include things
such as bug tracking.


=head2 Design goals

=over

=item Arbitrary record schema

=item Replication

=item Disconnected operation

=item Peer to peer synchronization

=back



=head2 Design constraints

=over

=item Scaling

We don't currently intend for the first implementation of Prophet to
scale to databases with millions of rows or hundreds of concurrent
users. There's nothing that makes the design infeasible, but the
infrastructure necessary for such a system will...needlessly hamstring it.

=back

=cut

1;
