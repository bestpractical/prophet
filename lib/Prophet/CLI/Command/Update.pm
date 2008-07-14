package Prophet::CLI::Command::Update;
use Moose;
extends 'Prophet::CLI::Command';
with 'Prophet::CLI::RecordCommand';

sub edit_record {
    my $self   = shift;
    my $record = shift;

    return $self->edit_props('edit', $record->get_props);
}

sub run {
    my $self = shift;

    my $record = $self->_load_record;
    my $result = $record->set_props( props => $self->edit_record($record) );
    if ($result) {
        print $record->type . " " . $record->uuid . " updated.\n";

    } else {
        print "SOMETHING BAD HAPPENED "
            . $record->type . " "
            . $record->uuid
            . " not updated.\n";

    }
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;

