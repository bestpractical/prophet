package Prophet::CLI::Command::Show;
use Moose;
extends 'Prophet::CLI::Command';
with 'Prophet::CLI::RecordCommand';


sub run {
    my $self = shift;

    my $record = $self->_load_record;
    print "id: ".$record->luid." (" .$record->uuid.")\n";
    my $props = $record->get_props();
    for ( keys %$props ) {
        print $_. ": " . $props->{$_} . "\n";
    }

}

__PACKAGE__->meta->make_immutable;
no Moose;

1;

