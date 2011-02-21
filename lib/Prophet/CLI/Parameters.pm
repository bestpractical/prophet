#!/usr/bin/env perl
package Prophet::CLI::Parameters;
use Any::Moose 'Role';

sub cli {
    return $Prophet::CLI::Dispatcher::cli;
}

sub context {
    my $self = shift;
    $self->cli->context;
}

no Any::Moose 'Role';

1;

