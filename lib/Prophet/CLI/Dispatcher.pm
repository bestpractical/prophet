package Prophet::CLI::Dispatcher;
use strict;
use warnings;
use Path::Dispatcher::Declarative -base;

# "ticket display $ID" -> "ticket display --id=$ID"
on qr{ (.*) \s+ ( \d+ | [A-Z0-9]{36} ) $ }x => sub {
    my $cli = shift;
    $cli->set_arg(id => $2);
    run($1, $cli, @_);
};

on qr{^(\w+)} => sub {
    my $cli = shift;
    my %args = @_;

    my $cmd = __PACKAGE__->resolve_builtin_aliases($1);

    my @possible_classes = (
        ("Prophet::CLI::Command::" . ucfirst lc $cmd),
        "Prophet::CLI::Command::Notound",
    );

    for my $class (@possible_classes) {
        if ($cli->_try_to_load_cmd_class($class)) {
            return $args{got_command}->($class);
        }
    }
};

my %CMD_MAP = (
    ls      => 'search',
    new     => 'create',
    edit    => 'update',
    rm      => 'delete',
    del     => 'delete',
    list    => 'search',
    display => 'show',
);

sub resolve_builtin_aliases {
    my $self = shift;
    my @cmds = @_;

    if (my $replacement = $CMD_MAP{ lc $cmds[-1] }) {
        $cmds[-1] = $replacement;
    }

    return wantarray ? @cmds : $cmds[-1];
}

1;

