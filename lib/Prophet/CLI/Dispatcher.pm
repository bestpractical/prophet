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

    my $class = join '::', split ' ', $1;
    $args{got_command}->($class);
};

1;

