package Prophet::CLI::Command::Show;
use Any::Moose;
use Params::Validate;
extends 'Prophet::CLI::Command';
with 'Prophet::CLI::RecordCommand';

sub ARG_TRANSLATIONS { shift->SUPER::ARG_TRANSLATIONS(),  'b' => 'batch' };

sub usage_msg {
    my $self = shift;
    my ($cmd, $type_and_subcmd) = $self->get_cmd_and_subcmd_names;

    return <<"END_USAGE";
usage: ${cmd}$type_and_subcmd <record-id> [--batch] [--verbose]
END_USAGE
}

sub run {
    my $self = shift;

    $self->print_usage if $self->has_arg('h');

    $self->require_uuid;
    my $record = $self->_load_record;

    print $self->stringify_props(
        record => $record,
        batch   => $self->has_arg('batch'),
        verbose => $self->has_arg('verbose'),
    );
}

=head2 stringify_props

Returns a stringified form of the properties suitable for displaying directly
to the user. Also includes luid and uuid.

=cut

sub stringify_props {
    my $self = shift;
    my %args = validate( @_, {record => { ISA => 'Prophet::Record'},
                            batch =>  1,
                            verbose => 1});

    my $record = $args{'record'};
    my $props = $record->get_props;


    # which props are we going to display?
    my @show_props;
    if ($record->can('props_to_show')) {
        @show_props = $record->props_to_show(\%args);

        # if they ask for verbosity, then display all the other fields
        # after the fields that our subclass wants to show
        if ($args{verbose}) {
            my %already_shown = map { $_ => 1 } @show_props;
            push @show_props, grep { !$already_shown{$_} }
                              sort keys %$props;
        }
    }
    else {
        @show_props = ('id', sort keys %$props);
    }

    # kind of ugly but it simplifies the code
    $props->{id} = $record->luid ." (" . $record->uuid . ")";

    my $max_length = 0;
    my @fields;

    for my $field (@show_props) {
        my $value = $props->{$field};

        # don't bother displaying unset fields
        next if !defined($value);

        push @fields, [$field, $value];

        $max_length = length($field) if length($field) > $max_length;
    }

    $max_length = 0 if $args{batch};

    return join '',
           map {
               my ($field, $value) = @$_;
               $field .= ':';
               $field .= ' ' x ($max_length - length($field));
               "$field $value\n"
           }
           @fields;
}

__PACKAGE__->meta->make_immutable;
no Any::Moose;

1;

