package Prophet::CLI::Command::Export;
use Any::Moose;
extends 'Prophet::CLI::Command';

sub run {
    my $self = shift;
    my $class;

    unless ($self->context->has_arg('path')) {
        die "You need to specify a --path argument to the 'export' command"."\n";
    }

    
    if ($self->context->has_arg('format') && ($self->context->arg('format') eq 'feed') ){
        $class = 'Prophet::ReplicaFeedExporter';
    } else {
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

