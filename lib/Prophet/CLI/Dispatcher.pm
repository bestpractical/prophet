package Prophet::CLI::Dispatcher;
use Path::Dispatcher::Declarative -base;
use Moose;

use Prophet::CLI;

has cli => (
    is       => 'rw',
    isa      => 'Prophet::CLI',
    required => 1,
);

has context => (
    is       => 'rw',
    isa      => 'Prophet::CLIContext',
    lazy     => 1,
    default  => sub {
        my $self = shift;
        $self->cli->context;
    },
);

has dispatching_on => (
    is       => 'rw',
    isa      => 'ArrayRef',
    required => 1,
);

on ['server'] => sub {
    my $self = shift;
    my $server = $self->setup_server;
    $server->run;
};

sub setup_server {
    my $self = shift;
    require Prophet::Server;
    my $server = Prophet::Server->new($self->context->arg('port') || 8080);
    $server->app_handle($self->context->app_handle);
    $server->setup_template_roots;
    return $server;
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;

