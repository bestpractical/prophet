package Prophet::CLI::Command::History;
use Moose;
extends 'Prophet::CLI::Command';
with 'Prophet::CLI::RecordCommand';

sub run {
    my $self = shift;

    $self->context->require_uuid;
    my $record = $self->_load_record;

    print $record->history_as_string;
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;


