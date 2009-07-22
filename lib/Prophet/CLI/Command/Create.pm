package Prophet::CLI::Command::Create;
use Any::Moose;
extends 'Prophet::CLI::Command';
with 'Prophet::CLI::RecordCommand';
has '+uuid' => ( required => 0);

has record => (
    is  => 'rw',
    isa => 'Prophet::Record',
    documentation => 'The record object of the created record.',
);

sub usage_msg {
    my $self = shift;
    my ($cmd, $type_and_subcmd) = $self->get_cmd_and_subcmd_names;

    return <<"END_USAGE";
usage: ${cmd}${type_and_subcmd} -- prop1=foo prop2=bar
END_USAGE
}

sub run {
    my $self   = shift;

    $self->print_usage if $self->has_arg('h');

    my $record = $self->_get_record_object;
    my ($val, $msg) = $record->create( props => $self->edit_props );
    if (!$val) {
        warn "Unable to create record: " . $msg . "\n";
    }
    if (!$record->uuid) {
        warn "Failed to create " . $record->record_type . "\n";
        return;
    }

    $self->record($record);

    print "Created " . $record->record_type . " " . $record->luid . " (".$record->uuid.")"."\n";
}

__PACKAGE__->meta->make_immutable;
no Any::Moose;

1;

