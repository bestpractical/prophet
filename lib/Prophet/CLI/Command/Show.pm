package Prophet::CLI::Command::Show;
use Moose;
use Params::Validate;
extends 'Prophet::CLI::Command';
with 'Prophet::CLI::RecordCommand';

sub run {
    my $self = shift;

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

You may define a "color_prop" method which transforms a property name and value
(by adding color).

You may also define a "color_prop_foo" method which transforms values of
property "foo" (by adding color).

=cut

sub stringify_props {
    my $self = shift;
    my %args = validate( @_, {record => { ISA => 'Prophet::Record'},
                            batch =>  1,
                            verbose => 1});

    my $record = $args{'record'};
    my $props = $record->get_props;

    my $colorize = $args{'batch'} ? 0 : 1;

    # which props are we going to display?
    my @show_props;
    if ($record->can('props_to_show')) {
        @show_props = $record->props_to_show(\%args);

        # if they ask for verbosity, then display all the other fields
        # after the fields that our subclass wants to show
        if ($args{verbose}) {
            my %already_shown = map { $_ => 1 } @show_props;
            push @show_props, grep { !$already_shown{$_} }
                              keys %$props;
        }
    }
    else {
        @show_props = ('id', keys %$props);
    }

    # kind of ugly but it simplifies the code
    $props->{id} = $record->luid ." (" . $record->uuid . ")";

    my $max_length = 0;
    my @fields;

    for my $field (@show_props) {
        my $value = $props->{$field};

        # don't bother displaying unset fields
        next if !defined($value);

        # color if we can (and should)
        my ($colorized_field, $colorized_value) = ($field, $value);
        if ($colorize) {
            ($colorized_field,$colorized_value) = $record->colorize($field => $value);

    }
        push @fields, [$field, $colorized_field, $colorized_value];

        # don't check length($field) here, since coloring will increase the
        # length but we only care about display length
        $max_length = length($field)
            if length($field) > $max_length;
    }

    $max_length = 0 if $args{batch};

    # this code is kind of ugly. we need to format based on uncolored length
    return join '',
           map {
               my ($field, $colorized_field, $colorized_value) = @$_;
               $colorized_field .= ':';
               $colorized_field .= ' ' x ($max_length - length($field));
               "$colorized_field $colorized_value\n"
           }
           @fields;
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;

