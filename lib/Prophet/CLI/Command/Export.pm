package Prophet::CLI::Command::Export;
use Any::Moose;
extends 'Prophet::CLI::Command';

sub usage_msg {
    my $self = shift;
    my $cmd = $self->cli->get_script_name;

    return <<"END_USAGE";
usage: ${cmd}export --path <path> [--format feed]
END_USAGE
}

sub run {
    my $self = shift;
    my $class;

    $self->print_usage if $self->has_arg('h');

    unless ($self->context->has_arg('path')) {
        warn "No --path argument specified!\n";
        $self->print_usage;
    }

    if ($self->context->has_arg('format') && ($self->context->arg('format') eq 'feed') ){
        $class = 'Prophet::ReplicaFeedExporter';
    }
    else {
        $class = 'Prophet::ReplicaExporter';
    }

    $self->app_handle->require ($class);
    my $exporter = $class->new(
        {   target_path    =>  $self->context->arg('path'),
            source_replica => $self->app_handle->handle,
            app_handle     => $self->app_handle
        }
    );

    $exporter->export();
}

__PACKAGE__->meta->make_immutable;
no Any::Moose;

1;

