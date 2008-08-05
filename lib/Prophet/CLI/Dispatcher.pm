package Prophet::CLI::Dispatcher;
use strict;
use warnings;
use Path::Dispatcher -base;

on qr{(.*)\s+(\d+)$} => sub {
    my $cli = shift;
    $cli->set_arg(id => $1);
    run($1, $args, @_);
};

1;

