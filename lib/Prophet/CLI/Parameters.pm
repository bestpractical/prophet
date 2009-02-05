#!/usr/bin/env perl
package Prophet::CLI::Parameters;
use Any::Moose 'Role';

has cli => (
    is       => 'rw',
    isa      => 'Prophet::CLI',
    required => 1,
);

has context => (
    is       => 'rw',
    isa      => 'Prophet::CLIContext',
    lazy     => 1,
    default  => sub {
        my $self = shift;
        $self->cli->context;
    },
);

no Any::Moose;

1;

