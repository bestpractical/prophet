package Prophet::CLI::Command::Server;
use Moose;
extends 'Prophet::CLI::Command';

sub run {

    my $self = shift;

    require Prophet::Server::REST;
    my $server = Prophet::Server::REST->new( $self->arg('port') || 8080 );
    $server->prophet_handle( $self->app_handle->handle );
    $server->run;
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;

