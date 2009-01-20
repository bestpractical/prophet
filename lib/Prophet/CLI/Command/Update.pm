package Prophet::CLI::Command::Update;
use Moose;
extends 'Prophet::CLI::Command';
with 'Prophet::CLI::RecordCommand';

sub edit_record {
    my $self   = shift;
    my $record = shift;

    my $props = $record->get_props;
    # don't feed in existing values if we're not interactively editing
    my $defaults = $self->has_arg('edit') ? $props : undef;

    my @ordering = ( );
    # we want props in $record->props_to_show to show up in the editor if --edit
    # is supplied too
    if ($record->can('props_to_show') && $self->has_arg('edit')) {
        @ordering = $record->props_to_show;
        map { $props->{$_} = '' if !exists($props->{$_}) } @ordering;
    }

    return $self->edit_props(arg => 'edit', defaults => $defaults,
        ordering => \@ordering);
}

sub run {
    my $self = shift;

    $self->context->require_uuid;
    my $record = $self->_load_record;

    my $new_props = $self->edit_record($record);

    # filter out props that haven't changed
    for my $prop (keys %$new_props) {
        delete $new_props->{$prop}
            if (($record->prop($prop) || '') eq $new_props->{$prop});
    }

    if (keys %$new_props) {
        my $result = $record->set_props( props => $new_props );

        if ($result) {
            print $record->type . " " . $record->luid . " (".$record->uuid.")"." updated.\n";

        } else {
            print "SOMETHING BAD HAPPENED "
                . $record->type . " "
                . $record->luid . " ("
                . $record->uuid
                . ") not updated.\n";
        }
    } else {
        print "No properties changed.\n";
    }
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;

