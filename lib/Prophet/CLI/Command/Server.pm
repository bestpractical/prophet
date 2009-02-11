package Prophet::CLI::Command::Server;
use Any::Moose;
extends 'Prophet::CLI::Command';

__PACKAGE__->register_arg_translations( p => 'port', w => 'writable' );

use Prophet::Server;

sub run {
    my $self = shift;
    Prophet::CLI->end_pager();
    my $server = $self->_setup_server();
    $server->run;
}

sub _setup_server {
    my $self = shift;
     my $server_class = ref($self->app_handle) . "::Server";
     if (!$self->app_handle->try_to_require($server_class)) {
         $server_class = "Prophet::Server";
     }
    my $server = $server_class->new( $self->arg('port') || 8080 );
    $server->app_handle( $self->app_handle );
    return $server;
}



__PACKAGE__->meta->make_immutable;
no Any::Moose;

1;

