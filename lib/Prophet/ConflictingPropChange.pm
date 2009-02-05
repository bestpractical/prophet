package Prophet::ConflictingPropChange;
use Any::Moose;

has name => (
    is  => 'rw',
    isa => 'Str',
);

has source_old_value => (
    is  => 'rw',
    isa => 'Str|Undef',
);

has target_value => (
    is  => 'rw',
    isa => 'Str|Undef',
);

has source_new_value => (
    is  => 'rw',
    isa => 'Str|Undef',
);

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

sub as_hash {
    my $self = shift;
    my $hashref = {};

    for (qw(name source_old_value target_value source_new_value)) {
         $hashref->{$_} = $self->$_
    }
    return $hashref;
}

__PACKAGE__->meta->make_immutable;
no Any::Moose;

1;
