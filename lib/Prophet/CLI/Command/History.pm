package Prophet::CLI::Command::History;
use Moose;
extends 'Prophet::CLI::Command';
with 'Prophet::CLI::RecordCommand';

sub run {
    my $self = shift;

    my $record = $self->_load_record;
    print "History for record " . $record->luid . " (" . $record->uuid . ")\n\n";
    for my $changeset ($record->changesets) {
        my @changes = grep { $_->record_uuid eq $record->uuid }
                     $changeset->changes;

        my $change = shift @changes;
        warn "We seem to have multiple changes for a single record for changeset ".$changeset->original_sequence_no .'@'.$changeset->original_source_uuid."\n" if ($changes[0]);

        my @prop_changes = $change->prop_changes;
        next if @prop_changes == 0;

        # separate each changeset
        print "Changeset ".$changeset->original_sequence_no .'@'.$changeset->original_source_uuid."\n";

        no warnings 'uninitialized'; # old changesets don't have creator
        print "by "
            . $changeset->creator . '@' . $changeset->original_source_uuid
            ." at " . $changeset->created . "\n";

        for my $prop_change (@prop_changes) {
            print "  ".$prop_change->summary, "\n";
        }

        print "\n";
    }
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;


