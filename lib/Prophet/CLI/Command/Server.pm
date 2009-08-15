package Prophet::CLI::Command::Server;
use Any::Moose;
extends 'Prophet::CLI::Command';

has server => (
    is      => 'rw',
    isa     => 'Maybe[Prophet::Server]',
    default => sub {
        my $self = shift;
        return $self->setup_server();
    },
    lazy    => 1,
);

sub ARG_TRANSLATIONS { shift->SUPER::ARG_TRANSLATIONS(),  p => 'port', w => 'writable' };

use Prophet::Server;

sub usage_msg {
    my $self = shift;
    my ($cmd, $subcmd) = $self->get_cmd_and_subcmd_names( no_type => 1 );

    return <<"END_USAGE";
usage: ${cmd}${subcmd} [--port <number>]
END_USAGE
}

sub run {
    my $self = shift;

    $self->print_usage if $self->has_arg('h');

    Prophet::CLI->end_pager();
    $self->server->run;
}

sub setup_server {
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

