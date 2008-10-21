#!/usr/bin/env perl
package Prophet::CLI::Shell;
use Moose;
with 'Prophet::CLI::Parameters';

has name => (
    is => 'ro',
    isa => 'Str',
    default => sub {
        require Path::Class;
        Path::Class::file($0)->basename
    },
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

    $self->_read_repl_history();

    $self->cli->interactive_shell(1);
    while ( defined(my $cmd = $self->read)) {
        next if $cmd =~ /^\s*$/;

        last if $cmd =~ /^\s*q(?:uit)?\s*$/i
             || $cmd =~ /^\s*exit\s*$/i;

        $self->eval($cmd);
    }

    $self->_write_repl_history();
}

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

