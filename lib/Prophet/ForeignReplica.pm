use warnings;
use strict;


package Prophet::ForeignReplica;
use base qw/Prophet::Replica/;

=head1 NAME

=head1 DESCRIPTION

This abstract baseclass implements the helpers you need to be able to easily sync a prophet replica with a "second class citizen" replica which can't exactly reconstruct changesets, doesn't use uuids to track records and so on.

=cut

1;
