package Prophet::CLI::Command::Create;
use Moose;
extends 'Prophet::CLI::Command';
with 'Prophet::CLI::RecordCommand';
has '+uuid' => ( required => 0);

sub run {
    my $self   = shift;
    my $record = $self->_get_record_class;
    my ($val, $msg) = $record->create( props => $self->edit_props );
    if (!$val) {
        warn "Unable to create record: " . $msg . "\n";
    }
    if (!$record->uuid) {
        warn "Failed to create " . $record->record_type . "\n";
        return;
    }

    print "Created " . $record->record_type . " " . $record->luid . " (".$record->uuid.")"."\n";

}

__PACKAGE__->meta->make_immutable;
no Moose;

1;

