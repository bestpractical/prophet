package Prophet::Resolver::Failed;
use Any::Moose;
use Data::Dumper;
extends 'Prophet::Resolver';
$Data::Dumper::Indent = 1;


sub run {
    my $self               = shift;
    my $conflicting_change = shift;
    my $conflict           = shift;

    die
        "The conflict was not resolved! Sorry dude."
        . Dumper($conflict, $conflicting_change);

}

__PACKAGE__->meta->make_immutable;
no Any::Moose;

1;
