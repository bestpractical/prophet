package Prophet::Resolver::Failed;
use Moose;
use Data::Dumper;
extends 'Prophet::Resolver';

sub run {
    my $self               = shift;
    my $conflicting_change = shift;
    my $conflict           = shift;

    die
        "The conflict was not resolved! Sorry dude."
        . Dumper($conflict, $conflicting_change);

}

__PACKAGE__->meta->make_immutable;
no Moose;

1;
