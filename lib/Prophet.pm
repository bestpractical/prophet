use warnings;
use strict;

package Prophet;

our $VERSION = '0.70';

=head1 NAME

Prophet

=head1 DESCRIPTION

Prophet is a distributed database system designed for small to medium
scale social database applications.  Our early targets include things
such as bug tracking.

=head2 Design goals

=head3 Arbitrary record schema

=head3 Replication

=head3 Disconnected operation

=head3 Peer to peer synchronization



=head2 Design constraints

=head3 Scaling

We don't currently intend for the first implementation of Prophet to
scale to databases with millions of rows or hundreds of concurrent
users. There's nothing that makes the design infeasible, but the
infrastructure necessary for such a system will...needlessly hamstring it.

=cut

1;
