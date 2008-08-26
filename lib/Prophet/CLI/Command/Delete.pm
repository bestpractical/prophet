package Prophet::CLI::Command::Delete;
use Moose;
extends 'Prophet::CLI::Command';
with 'Prophet::CLI::RecordCommand';

sub run {
    my $self = shift;

    $self->require_uuid;
    my $record = $self->_load_record;

    if ( $record->delete ) {
        print $record->type . " " . $record->uuid . " deleted.\n";
    } else {
        print $record->type . " " . $record->uuid . "could not be deleted.\n";
    }

}

__PACKAGE__->meta->make_immutable;
no Moose;

1;

