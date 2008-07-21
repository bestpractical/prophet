package Prophet::CLI::Command::Server;
use Moose;
extends 'Prophet::CLI::Command';

use Prophet::Server;

sub run {

    my $self = shift;

    my $server = Prophet::Server->new( $self->arg('port') || 8080 );
    $server->prophet_handle( $self->app_handle->handle );
    $server->run;
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;

