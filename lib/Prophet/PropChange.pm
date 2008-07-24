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

sub summary {
    my $self = shift;
    my $name = $self->name;
    my $old  = $self->old_value;
    my $new  = $self->new_value;

    if (!defined($old)) {
        return sprintf 'Property "%s" was added, value "%s".',
               $name,
               $new;
    }
    elsif (!defined($new)) {
        return sprintf 'Property "%s" was removed, value was "%s".',
               $name,
               $new;
    }

    return sprintf 'Property "%s" changed from "%s" to "%s".',
           $name,
           $old,
           $new;
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;
