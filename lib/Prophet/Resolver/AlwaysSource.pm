package Prophet::Resolver::AlwaysSource;
use Any::Moose;
use Prophet::Change;
extends 'Prophet::Resolver';

sub run {
    my $self               = shift;
    my $conflicting_change = shift;
    return 0 if $conflicting_change->file_op_conflict;

    my $resolution = Prophet::Change->new_from_conflict($conflicting_change);
    return $resolution;
}

__PACKAGE__->meta->make_immutable;
no Any::Moose;

1;
