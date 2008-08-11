#!/usr/bin/env perl
package Prophet::CLI::Command::Shell;
use Moose;
extends 'Prophet::CLI::Command';
use Path::Class 'file';

has name => (
    is => 'ro',
    isa => 'Str',
    default => sub { file($0)->basename },
);

has term => (
    is      => 'ro',
    isa     => 'Term::ReadLine',
    lazy    => 1,
    handles => [qw/readline addhistory/],
    default => sub {
        require Term::ReadLine;
        return Term::ReadLine->new("Prophet shell");
    },
);

sub prompt {
    my $self = shift;
    return $self->name . '> ';
}

sub run {
    my $self = shift;

    local $| = 1;

    while (defined(local $_ = $self->readline($self->prompt))) {
        next if /^\s*$/;

        local @ARGV = split ' ', $_;
        eval { $self->run_one_command };
        warn $@ if $@;
    }
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;

