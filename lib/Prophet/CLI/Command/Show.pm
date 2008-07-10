package Prophet::CLI::Command::Show;
use Moose;
extends 'Prophet::CLI::Command';
with 'Prophet::CLI::RecordCommand';


sub run {
    my $self = shift;

    my $record = $self->_load_record;
    print $record->show_props;
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;

