#!/usr/bin/env perl
package Prophet::CLI::Command::Shell;
use Moose;
extends 'Prophet::CLI::Command';
use Path::Class 'file';

sub prompt {
    my $binary = file($0)->basename;
    return "$binary> ";
}

sub run {
    my $self = shift;

    local $| = 1;

    while (1) {
        print $self->prompt;
        my $input = <>;
        last if !defined($input);

        local @ARGV = split ' ', $input;
        eval { $self->run_one_command };
        warn $@ if $@;
    }
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;

