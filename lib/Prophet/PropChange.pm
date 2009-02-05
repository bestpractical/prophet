package Prophet::PropChange;
use Any::Moose;

has name => (
    is  => 'rw',
    isa => 'Str',
);

has old_value => (
    is  => 'rw',
    isa => 'Str|Undef',
);

has new_value => (
    is  => 'rw',
    isa => 'Str|Undef',
);

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

sub summary {
    my $self = shift;
    my $name = $self->name || '(property name missing)';
    my $old  = $self->old_value;
    my $new  = $self->new_value;

    if (!defined($old)) {
        return qq{+ "$name" set to "}.($new||'').qq{"};
    }
    elsif (!defined($new)) {
        return qq{- "$name" "$old" deleted.};
    }

    return qq{> "$name" changed from "$old" to "$new".};
}

__PACKAGE__->meta->make_immutable;
no Any::Moose;

1;
