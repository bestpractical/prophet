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

on qr{(.*)} => sub {
    my $cli = shift;
    my %args = @_;

    my @possible_classes;

    my @pieces = split ' ', $1;

    for my $main ($cli->app_class, "Prophet") {
        push @possible_classes, $main
                              . "::CLI::Command::"
                              . ucfirst lc $pieces[-1];
    }

    for my $main ($cli->app_class, "Prophet") {
        push @possible_classes, $main . "::CLI::Command::NotFound";
    }

    for my $class (@possible_classes) {
        if ($cli->_try_to_load_cmd_class($class)) {
            return $args{got_command}->($class);
        }
    }
};

1;

