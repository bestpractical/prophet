package Prophet::CLI::Command::History;
use Moose;
extends 'Prophet::CLI::Command';
with 'Prophet::CLI::RecordCommand';

sub run {
    my $self = shift;

    my $record = $self->_load_record;
    print "History for record " . $record->luid . " (" . $record->uuid . ")\n";
    for my $change ($record->changes) {
        my @prop_changes = $change->prop_changes;
        next if @prop_changes == 0;

        # separate each changeset
        print "\n";

        for my $prop_change (@prop_changes) {
            print $prop_change->summary, "\n";
        }
    }
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;


