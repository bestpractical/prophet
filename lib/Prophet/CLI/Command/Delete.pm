package Prophet::CLI::Command::Delete;
use Any::Moose;
extends 'Prophet::CLI::Command';
with 'Prophet::CLI::RecordCommand';

sub usage_msg {
    my $self = shift;
    my ($cmd, $type_and_subcmd) = $self->get_cmd_and_subcmd_names;

    return <<"END_USAGE";
usage: ${cmd}${type_and_subcmd} <id>
END_USAGE
}

sub run {
    my $self = shift;

    $self->print_usage if $self->has_arg('h');

    $self->require_uuid;
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

