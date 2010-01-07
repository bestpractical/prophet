package Prophet::CLI::Dispatcher::Rule;
use Any::Moose;
extends 'Path::Dispatcher::Rule';

has cli => (
    is        => 'rw',
    isa       => 'Prophet::CLI',
    weak_ref  => 1,
    predicate => 'has_cli',
);

__PACKAGE__->meta->make_immutable;
no Any::Moose;

1;

