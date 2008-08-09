package Prophet::CLI::Command::History;
use Moose;
extends 'Prophet::CLI::Command';
with 'Prophet::CLI::RecordCommand';

sub run {
    my $self = shift;

    $self->require_uuid;
    my $record = $self->_load_record;

    print "History for record " . $record->luid . " (" . $record->uuid . ")\n\n";
    for my $changeset ($record->changesets) {
        print $changeset->as_string(change_filter => sub {
            shift->record_uuid eq $record->uuid
        });
    }
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;


