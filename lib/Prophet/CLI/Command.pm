#!/usr/bin/env perl
package Prophet::CLI::Command;
use Moose;
with 'Prophet::CLI::Parameters';

__PACKAGE__->meta->make_immutable;
no Moose;

1;

