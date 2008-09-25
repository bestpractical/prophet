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
    isa     => 'Term::ReadLine::Stub',
    lazy    => 1,
    handles => [qw/readline addhistory/],
    default => sub {
        require Term::ReadLine;
        return Term::ReadLine->new("Prophet shell");
    },
);

    our $HIST = $ENV{PROPHET_HISTFILE}
            || (($ENV{HOME} || (getpwuid($<))[7]) . "/.prophetreplhist");
    our $LEN = $ENV{PROPHET_HISTLEN} || 500;




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

    eval {
        local $SIG{__DIE__} = 'DEFAULT';
        $self->cli->run_one_command(split ' ', $line);
    };
    warn $@ if $@;
}

sub run {
    my $self = shift;

    local $| = 1;

    print $self->preamble . "\n";

    $self->cli->interactive_shell(1);
    while ( defined(my $cmd = $self->read)) {
        next if $cmd =~ /^\s*$/;

        last if $cmd =~ /^\s*q(?:uit)?\s*$/i
             || $cmd =~ /^\s*exit\s*$/i;

        $self->eval($cmd);
    }
}

# make the REPL history persistent
around run => sub {
    my $orig = shift;
    my $self = shift;
    $self->_read_repl_history();
    $self->$orig(@_);
    $self->_write_repl_history();
};


# we use eval here because only some Term::ReadLine subclasses support
# persistent history. it also seems that ->can doesn't work because of AUTOLOAD
# trickery. :(

sub _read_repl_history {
    my $self = shift;
    eval {
        local $SIG{__DIE__};
        $self->term->stifle_history($LEN);
        $self->term->ReadHistory($HIST)
            if -f $HIST;
    };
}

sub _write_repl_history {
    my $self = shift;

    eval {
        local $SIG{__DIE__};
        $self->term->WriteHistory($HIST)
            or warn "Unable to write to shell history file $HIST";
    };
}


__PACKAGE__->meta->make_immutable;
no Moose;

1;

