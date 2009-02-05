package Prophet::CLI::RecordCommand;
use Any::Moose 'Role';
use Params::Validate;
use Prophet::Record;


has type => (
    is        => 'rw',
    isa       => 'Str',
    required  => 0,
    predicate => 'has_type',
);

has uuid => (
    is        => 'rw',
    isa       => 'Str',
    required  => 0,
    predicate => 'has_uuid',
);

has record_class => (
    is  => 'rw',
    isa => 'Prophet::Record',
);

=head2 _get_record_object [{ type => 'type' }]

Tries to determine a record class from either the given type argument or
the current object's C<$type> attribute.

Returns a new instance of the record class on success, or throws a fatal
error with a stack trace on failure.

=cut

sub _get_record_object {
    my $self = shift;
    my %args = validate(@_, {
        type => { default => $self->type },
    });

    my $constructor_args = {
        app_handle => $self->cli->app_handle,
        handle     => $self->cli->handle,
        type       => $args{type},
    };

    if ($args{type}) {
        my $class = $self->_type_to_record_class($args{type});
        return $class->new($constructor_args);
    }
    elsif (my $class = $self->record_class) {
        Prophet::App->require($class);
        return $class->new($constructor_args);
    }
    else {
       $self->fatal_error("I couldn't find that record. (You didn't specify a record type.)");
    }
}

=head2 _load_record

Attempts to load the record specified by the C<uuid> attribute.

Returns the loaded record on success, or throws a fatal error if no
record can be found.

=cut

sub _load_record {
    my $self = shift;
    my $record = $self->_get_record_object;
    $record->load( uuid => $self->uuid )
        || $self->fatal_error("I couldn't find the " . $self->type . ' ' . $self->uuid);
    return $record;
}

=head2 _type_to_record_class $type

Takes a type and tries to figure out a record class name from it.
Returns C<'Prophet::Record'> if no better class name is found.

=cut

sub _type_to_record_class {
    my $self = shift;
    my $type = shift;
    my $try = $self->cli->app_class . "::Model::" . ucfirst( lc($type) );
    Prophet::App->try_to_require($try);    # don't care about fails
    return $try if ( $try->isa('Prophet::Record') );

    $try = $self->cli->app_class . "::Record";
    Prophet::App->try_to_require($try);    # don't care about fails
    return $try if ( $try->isa('Prophet::Record') );
    return 'Prophet::Record';
}

no Any::Moose;

1;

