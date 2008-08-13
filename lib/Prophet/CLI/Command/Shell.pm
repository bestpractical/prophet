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

sub preamble {
    return join "\n",
        "Prophet $Prophet::VERSION",
        'Type "help", "about", or "copying" for more information.',
}

sub read {
    my $self = shift;
    $self->readline($self->prompt);
}

sub eval {
    my $self = shift;
    my $line = shift;

    local @ARGV = split ' ', $line;

    eval {
        local $SIG{__DIE__} = 'DEFAULT';
        $self->cli->run_one_command;
    };
    warn $@ if $@;
}

sub run {
    my $self = shift;

    local $| = 1;

    print $self->preamble . "\n";

    $self->cli->interactive_shell(1);
    while (defined(local $_ = $self->read)) {
        next if /^\s*$/;

        last if /^\s*q(?:uit)?\s*$/i
             || /^\s*exit\s*$/i;

        $self->eval($_);
    }
}

# make the REPL history persistent
around run => sub {
    my $orig = shift;
    my $self = shift;

    my $hist = $ENV{PROPHET_HISTFILE}
            || (($ENV{HOME} || (getpwuid($<))[7]) . "/.prophetreplhist");
    my $len = $ENV{PROPHET_HISTLEN} || 100;

    $self->term->stifle_history($len);
    $self->term->ReadHistory($hist)
        if -f $hist;

    $self->$orig(@_);

    $self->term->WriteHistory($hist)
        or warn "Unable to write to shell history file $hist";
};

__PACKAGE__->meta->make_immutable;
no Moose;

1;

