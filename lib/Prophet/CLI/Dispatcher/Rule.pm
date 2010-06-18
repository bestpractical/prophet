package Prophet::CLI::Dispatcher::Rule;
use Any::Moose 'Role';

has cli => (
    is        => 'rw',
    isa       => 'Prophet::CLI',
    weak_ref  => 1,
    predicate => 'has_cli',
);

no Any::Moose 'Role';

1;

