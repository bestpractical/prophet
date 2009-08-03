package Prophet::CLI::Command::History;
use Any::Moose;
extends 'Prophet::CLI::Command';
with 'Prophet::CLI::RecordCommand';

sub usage_msg {
    my $self = shift;
    my ($cmd, $type_and_subcmd) = $self->get_cmd_and_subcmd_names;

    return <<"END_USAGE";
usage: ${cmd}${type_and_subcmd} <record>
END_USAGE
}

sub run {
    my $self = shift;

    $self->print_usage if $self->has_arg('h');

    $self->require_uuid;
    my $record = $self->_load_record;

    print $record->history_as_string;
}

__PACKAGE__->meta->make_immutable;
no Any::Moose;

1;


