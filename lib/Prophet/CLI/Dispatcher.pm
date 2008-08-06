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

    my @possible_classes = (
        ("Prophet::CLI::Command::" . ucfirst lc $1),
        "Prophet::CLI::Command::Notound",
    );

    for my $class (@possible_classes) {
        if ($cli->_try_to_load_cmd_class($class)) {
            return $args{got_command}->($class);
        }
    }
};

1;

