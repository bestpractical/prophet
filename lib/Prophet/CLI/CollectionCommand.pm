package Prophet::CLI::CollectionCommand;
use Moose::Role;
with 'Prophet::CLI::RecordCommand';

use Params::Validate;

sub get_collection_object {
    my $self = shift;
    my %args = validate(@_, {
        type => { default => $self->type },
    });

    my $record_class = $self->_get_record_class(type => $args{type});
    my $class = $record_class->collection_class;
    Prophet::App->require($class);

    my $records = $class->new(
        app_handle => $self->app_handle,
        handle     => $self->app_handle->handle,
        type       => $args{type} || $self->type,
    );

    return $records;
}

no Moose::Role;

1;

