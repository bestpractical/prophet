#!/usr/bin/env perl
package Prophet::CLI::CollectionCommand;
use Moose::Role;

sub get_collection_object {
    my $self = shift;
    my %args = @_;

    my $class = $self->_get_record_class->collection_class;
    Prophet::App->require_module($class);

    my $records = $class->new(
        app_handle => $self->app_handle,
        handle     => $self->app_handle->handle,
        type       => $args{type} || $self->type,
    );

    return $records;
}

no Moose::Role;

1;

