package Prophet::CLI::CollectionCommand;
use Any::Moose 'Role';
with 'Prophet::CLI::RecordCommand';

use Params::Validate;

sub get_collection_object {
    my $self = shift;
    my %args = validate(@_, {
        type => { default => $self->type },
    });

    my $class = $self->_get_record_object(type => $args{type})->collection_class;
    Prophet::App->require($class);

    my $records = $class->new(
        app_handle => $self->app_handle,
        handle     => $self->handle,
        type       => $args{type} || $self->type,
    );

    return $records;
}

no Any::Moose;

1;

