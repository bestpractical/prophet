package Prophet::CLI::Command::Delete;
use Any::Moose;
extends 'Prophet::CLI::Command';
with 'Prophet::CLI::RecordCommand';

sub run {
    my $self = shift;

    $self->context->require_uuid;
    my $record = $self->_load_record;

    if ( $record->delete ) {
        print $record->type . " " . $record->uuid . " deleted.\n";
    } else {
        print $record->type . " " . $record->uuid . "could not be deleted.\n";
    }

}

__PACKAGE__->meta->make_immutable;
no Any::Moose;

1;

