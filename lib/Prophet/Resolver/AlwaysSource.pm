use warnings;
use strict;

package Prophet::Resolver::AlwaysSource;
use base qw/Prophet::Resolver/;
use Prophet::Change;

sub run {
    my $self     = shift;
    my $conflicting_change = shift;
    return 0 if $conflicting_change->file_op_conflict;

    my $resolution = Prophet::Change->new_from_conflict($conflicting_change);
    return $resolution;
}

1;
