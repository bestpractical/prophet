package Prophet::PropChange;
use Moose;

has name => (
    is  => 'rw',
    isa => 'Str',
);

has old_value => (
    is  => 'rw',
    isa => 'Maybe[Str]',
);

has new_value => (
    is  => 'rw',
    isa => 'Maybe[Str]',
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

__PACKAGE__->meta->make_immutable;
no Moose;

1;
