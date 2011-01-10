package Prophet::Record;
use Any::Moose;
use Params::Validate;
use Term::ANSIColor;
use Prophet::App; # for require_module. Kinda hacky
use constant collection_class => 'Prophet::Collection';

=head1 NAME

Prophet::Record

=head1 DESCRIPTION

This class represents a base class for any record in a Prophet database.

=cut

has app_handle => (
    isa      => 'Prophet::App|Undef',
    is       => 'rw',
    required => 0,
);

has handle => (
    is       => 'rw',
    required => 1,
    lazy     => 1,
    default  => sub { shift->app_handle->handle }
);

has type => (
    is        => 'rw',
    isa       => 'Str',
    predicate => 'has_type',
    required => 1,
    default   => sub { undef}
);

has uuid => (
    is      => 'rw',
    isa     => 'Str',
);

has luid => (
    is  => 'rw',
    isa => 'Str|Undef',
    lazy => 1,
    default => sub { my $self = shift; $self->find_or_create_luid; },
);

our $REFERENCES = {};
sub REFERENCES { $REFERENCES }

our $PROPERTIES = {};
sub PROPERTIES { $PROPERTIES }

=head1 METHODS

=head2 new  { handle => Prophet::Replica, type => $type }

Instantiates a new, empty L<Prophet::Record> of type $type.

=head2 declared_props

Returns a sorted list of the names of the record's declared properties.
Declared properties are always validated even if the user provides no value
for that prop. This can be used for such things as requiring records to
have certain props in order to be created, for example.

=cut

sub declared_props {
    return sort keys %{ $_[0]->PROPERTIES };
}

=head2 record_type

Returns the record's type.

=cut

sub record_type { $_[0]->type }

=head2 register_reference $class, $accessor, $foreign_class, @args

Registers a reference to a foreign class to this record. The
foreign class must be of type L<Prophet::Collection> or
L<Prophet::Record>, or else a fatal error is triggered.

=cut

sub register_reference {
    my ( $class, $accessor, $foreign_class, @args ) = @_;
    Prophet::App->require($foreign_class);
    if ( $foreign_class->isa('Prophet::Collection') ) {
        return $class->register_collection_reference(
            $accessor => $foreign_class,
            @args
        );
    } elsif ( $foreign_class->isa('Prophet::Record') ) {
        return $class->register_record_reference(
            $accessor => $foreign_class,

            # default the lookup property to be the name of the accessor
            by        => $accessor,

            @args
        );
    } else {
        die "Your foreign class ($foreign_class) must be a subclass of Prophet::Record or Prophet::Collection";
    }

}

=head2 register_collection_reference $accessor, $collection_class, by => $key_in_model

Registers and creates an accessor in the current class to the associated
collection C<$collection_class>, which refers to the current class by
C<$key_in_model> in the model class of C<$collection_class>.

=cut

sub register_collection_reference {
    my ( $class, $accessor, $collection_class, @args ) = @_;
    my %args = validate( @args, { by => 1 } );
    no strict 'refs';

    Prophet::App->require( $collection_class->record_class );

    *{ $class . "::$accessor" } = sub {
        my $self       = shift;
        my $collection = $collection_class->new(
            app_handle => $self->app_handle,
        );
        $collection->matching( sub { ($_[0]->prop( $args{by} )||'') eq $self->uuid }
        );
        return $collection;
    };

    # XXX: add validater for $args{by} in $model->record_class

    $class->REFERENCES->{$class}{$accessor} = {
        %args,
        arity => 'collection',
        type  => $collection_class->record_class,
    };
}

=head2 register_record_reference $accessor, $record_class, by => $key_in_model

Registers and creates an accessor in the current class to the associated
record C<$record_class>, which refers to the current class by
C<$key_in_model> in the model class of C<$collection_class>.

=cut

sub register_record_reference {
    my ( $class, $accessor, $record_class, @args ) = @_;
    my %args = validate( @args, { by => 1 } );
    no strict 'refs';

    Prophet::App->require( $record_class );

    *{ $class . "::$accessor" } = sub {
        my $self       = shift;
        my $record = $record_class->new(
            app_handle => $self->app_handle,
            handle     => $self->handle,
        );
        $record->load(uuid => $self->prop($args{by}));
        return $record;
    };

    # XXX: add validater for $args{by} in $model->record_class

    $class->REFERENCES->{$class}{$accessor} = {
        %args,
        arity => 'scalar',
        type  => $record_class,
    };
}

=head2 create { props => { %hash_of_kv_pairs } }

Creates a new Prophet database record in your database. Sets the record's properties to the keys and values passed in.

Automatically canonicalizes and then validates the props.

Upon successful creation, returns the new record's C<uuid>.
In case of failure, returns undef.

=cut

sub create {
    my $self = shift;
    my %args = validate( @_, { props => 1 } );
    my $uuid = $self->handle->uuid_generator->create_str;

    my $props = $args{props};

    $self->default_props($props);
    $self->canonicalize_props($props); 

    # XXX TODO - this should be a real exception 
    return undef unless (keys %$props);

    $self->validate_props($props) or return undef;
    $self->_create_record(props => $props, uuid => $uuid);
}




# _create_record is a helper routine, used both by create and by databasesetting::create
sub _create_record {
    my $self = shift;
    my %args = validate( @_, { props => 1, uuid => 1 } );

    $self->uuid($args{uuid});

    $self->handle->create_record(
        props => $args{'props'},
        uuid  => $self->uuid,
        type  => $self->type
    );

    return $self->uuid;

}

=head2 load { uuid => $UUID } or { luid => $UUID }

Given a UUID or LUID, look up the LUID or UUID (the opposite of what was
given) in the database. Set this record's LUID and UUID attributes, and return
the LUID or UUID (whichever wasn't given in the method call).

Returns undef if the record doesn't exist in the database.

=cut

sub load {
    my $self = shift;

    my %args = validate(
        @_,
        {   uuid => {
                optional  => 1,
                callbacks => {
                    'uuid or luid present' => sub { $_[0] || $_[1]->{luid} },
                },
            },
            luid => {
                optional  => 1,
                callbacks => {
                    'luid or uuid present' => sub { $_[0] || $_[1]->{uuid} },
                },
            },
        }
    );

    if ( $args{luid} ) {
        $self->luid( $args{luid} );
        $self->uuid( $self->handle->find_uuid_by_luid( luid => $args{luid} ) );
        return($self->uuid) if ($self->uuid);
    } else {
        $self->uuid( $args{uuid} );
        $self->luid( $self->handle->find_or_create_luid( uuid => $args{uuid}));
        return($self->luid) if ($self->luid);
    }

    return undef;
}

# a private method to let collection search results instantiate records more quickly
# (See Prophet::Replica::sqlite)
sub _instantiate_from_hash {
    my $self = shift;
    my %args = ( uuid => undef, luid => undef, @_);
    # we might not have a luid cheaply (see the prophet filesys backend)
    $self->luid($args{'luid'}) if (defined $args{'luid'});
    # We _Always_ have a luid
    $self->uuid($args{'uuid'});
    # XXX TODO - expect props as well
}

sub loaded {
    my $self = shift;
    return $self->uuid ? 1 : 0;
}

=head2 set_prop { name => $name, value => $value }

Updates the current record to set an individual property called C<$name> to C<$value>

This is a convenience method around L</set_props>.

=cut

sub set_prop {
    my $self = shift;

    my %args = validate( @_, { name => 1, value => 1 } );
    my $props = { $args{'name'} => $args{'value'} };
    $self->set_props( props => $props );
}

=head2 set_props { props => { key1 => val1, key2 => val2} }

Updates the current record to set all the keys contained in the C<props> parameter to their associated values.
Automatically canonicalizes and validates the props in question.

In case of failure, returns false.

On success, returns true.

=cut

sub set_props {
    my $self = shift;
    my %args = validate( @_, { props => 1 } );

    confess "set_props called on a record that hasn't been loaded or created yet." if !$self->uuid;

    $self->canonicalize_props( $args{'props'} );
    $self->validate_props( $args{'props'} ) || return undef;

    return 0 unless grep { defined } values %{$args{props}}; 

    $self->handle->set_record_props(
        type  => $self->type,
        uuid  => $self->uuid,
        props => $args{'props'}
    );
    return 1;
}

=head2 get_props

Returns a hash of this record's properties as currently set in the database.

=cut

sub get_props {
    my $self = shift;

    confess "get_props called on a record that hasn't been loaded or created yet." if !$self->uuid;

    return $self->handle->get_record_props(
        uuid => $self->uuid,
        type => $self->type) || {};

}

=head2 exists

When called on a loaded record, returns true if the record exists and false if it does not.

=cut

sub exists {
    my $self = shift;
    return $self->handle->record_exists( uuid => $self->uuid, type => $self->type);
}

=head2 prop $name

Returns the current value of the property C<$name> for this record.
(This is a convenience method wrapped around L</get_props>).

=cut

sub prop {
    my $self = shift;
    my $prop = shift;
    return $self->get_props->{$prop};
}

=head2 delete_prop { name => $name }

Deletes the current value for the property $name.
(This is currently equivalent to setting the prop to ''.)

=cut

sub delete_prop {
    my $self = shift;
    my %args = validate( @_, { name => 1 } );

    confess "delete_prop called on a record that hasn't been loaded or created yet." if !$self->uuid;

    $self->set_prop(name => $args{'name'}, value => '');

#    $self->handle->delete_record_prop(
#        uuid => $self->uuid,
#        name => $args{'name'}
#    );
}

=head2 delete

Deletes this record from the database. (Note that it does _not_ purge historical versions of the record)

=cut

sub delete {
    my $self = shift;
    delete $self->{props};
    $self->handle->delete_record( type => $self->type, uuid => $self->uuid );

}

=head2 changesets { limit => $int } 

Returns an ordered list of changeset objects for all changesets containing
changes to the record specified by this record object.

Note that changesets may include changes to other records.

If a limit is specified, this routine will only return that many
changesets, starting from the changeset containing the record's
creation.

=cut

sub changesets {
    my $self = shift;
    my %args = validate(@_, { limit => 0});
    return $self->handle->changesets_for_record(
        uuid => $self->uuid,
        type => $self->type,
        $args{limit} ? (limit => $args{limit}) : ()
    );
}

=head2 changes

Returns an ordered list of all the change objects that represent changes
to the record specified by this record object.

=cut

sub changes {
    my $self = shift;
    my $uuid = $self->uuid;
    my @changesets = $self->changesets;

    return grep { $_->record_uuid eq $uuid }
            map { $_->changes }
            @changesets;
}

=head2 uniq @list

The C<List::MoreUtils::uniq> function (taken from version 0.21).

Returns a new list by stripping duplicate values in @list. The order of
elements in the returned list is the same as in @list. In scalar
context, returns the number of unique elements in @list.

    my @x = uniq 1, 1, 2, 2, 3, 5, 3, 4; # returns 1 2 3 5 4
    my $x = uniq 1, 1, 2, 2, 3, 5, 3, 4; # returns 5

=cut

sub uniq (@) { my %h; map { $h{$_}++ == 0 ? $_ : () } @_; }

=head2 validate_props $propsref

Takes a reference to a props hash and validates each prop in the
hash or in the C<PROPERTIES> attribute that has a validation routine
(C<validate_prop_$prop>).

Dies if any prop fails validation. Returns true on success. Returns
false if any prop is not allowable (prop name fails validation).

=cut

sub validate_props {
    my $self   = shift;
    my $props  = shift;
    my $errors = {};
    my @errors;
    for my $key ( uniq( keys %$props, $self->declared_props ) ) {
        return undef unless ( $self->_validate_prop_name($key) );
        if ( my $sub = $self->can( 'validate_prop_' . $key ) ) {
            $sub->( $self, props => $props, errors => $errors ) ||
                push @errors,"Validation error for '$key': " .
                    ( $errors->{$key} || '' ) . '.';
        }
    }
    if (@errors) {
        die join( "\n", @errors )."\n";
    }
    return 1;
}

=head2 _validate_prop_name

A hook to allow forcing users to only use certain prop names.

Currently just returns true for all inputs.

=cut

sub _validate_prop_name {1}

=head2 canonicalize_props $propsref

Takes a hashref to a props hash and canonicalizes each one if a
C<canonicalize_prop_$prop> routine is available.

Returns true on completion.

=cut

sub canonicalize_props {
    my $self   = shift;
    my $props  = shift;
    my $errors = {};
    for my $key ( uniq( keys %$props, $self->declared_props ) ) {
        $self->canonicalize_prop($key, $props, $errors);
    }
    return 1;
}

sub canonicalize_prop {
    my $self = shift;
    my $prop = shift;
    my $props = shift;
    my $errors = shift;
        if ( my $sub = $self->can( 'canonicalize_prop_' . $prop ) ) {
            $sub->( $self, props => $props, errors => $errors );
            return 1;
        }


    return 0;
}


=head2 default_props $props_ref

Takes a reference to a hash of props and looks up the defaults for those
props, if they exist (by way of C<default_prop_$prop> routines). Sets the
values of the props in the hash to the defaults.

=cut

sub default_props {
    my $self   = shift;
    my $props  = shift;

    my @methods = grep { /^default_prop_/ } $self->meta->get_all_method_names;

    for my $method (@methods) {
        my ($key) = $method =~ /^default_prop_(.+)$/;

        $props->{$key} = $self->$method(props => $props)
            if !defined($props->{$key});
    }

    return 1;
}

=head2 default_prop_creator

Default the creator of every record to the changeset_creator (usually the current user's email address.)

=cut

sub default_prop_creator {
    my $self = shift;
    return $self->handle->changeset_creator;
}

=head2 default_prop_original_replica

Default the original_replica of every record to the replica's uuid.

=cut

sub default_prop_original_replica {
    my $self = shift;
    return $self->handle->uuid;
}

=head2 validate_prop_from_recommended_values 'prop', $argsref

Checks to see if the given property has a valid value and returns true if so.
If not, adds an error message to $argsref->{errors}{prop} and returns false.

=cut

sub validate_prop_from_recommended_values {
    my $self = shift;
    my $prop = shift;
    my $args = shift;

    if ( my @options = $self->recommended_values_for_prop($prop) ) {
        return 1 if ((scalar grep { $args->{props}{$prop} eq $_ } @options)
            # force-set props with ! to bypass validation
            || $args->{props}{$prop} =~ s/!$//);

        $args->{errors}{$prop}
            = "'" . $args->{props}->{$prop} . "' is not a valid $prop";
        return 0;
    }
    return 1;

}

=head2 recommended_values_for_prop 'prop'

Given a record property, return an array of the values that should usually be
associated with this property.

If a property doesn't have a specific range of values, undef is
returned.

This is mainly intended for use in prop validation (see
L<validate_prop_from_recommended_values>). Recommended values for a
prop are set by defining methods called C<_recommended_values_for_prop_$prop>
in application modules that inherit from L<Prophet::Record>.

=cut

sub recommended_values_for_prop {
    my $self = shift;
    my $prop = shift;

    if (my $code = $self->can("_recommended_values_for_prop_".$prop)) {
        $code->($self, @_);
    } else {
        return undef;
    }
    
}

=head2 _default_summary_format

A string of the default summary format for record types that do not
define their own summary format.

A summary format should consist of format_string,field pairs, separated
by | characters.

Fields that are not property names must start with the C<$> character and be
handled in the C<atom_value> routine.

Example:

C<'%s,$luid | %s,summary | %s,status'>

=cut

sub _default_summary_format {  undef }

=head2 _summary_format

Tries to find the summary format for the record type. Returns
L<_default_summary_format> if nothing better can be found.

=cut

sub _summary_format {
    my $self = shift;
    return
        $self->app_handle->config->get( key => $self->type.'.summary-format' )
        || $self->app_handle->config->get( key => 'record.summary-format' )
        || $self->_default_summary_format;
}

=head2 _atomize_summary_format [$format]

Splits a summary format into pieces (separated by arbitrary whitespace and
the | character). Returns the split list.

If no summary format is supplied, this routine attempts to find one by
calling L<_summary_format>.

=cut

sub _atomize_summary_format {
    my $self = shift;
    my $format = shift || $self->_summary_format;

    return undef unless $format;
    return split /\s*\|\s*/, $format;
}

=head2 _parse_format_summary

Parses the summary format for this record's type (or the default summary
format if no type-specific format exists).

Returns a list of hashrefs to hashes which contain the following keys:
C<format>, C<prop>, C<value>, and C<formatted>

(These are the format string, the property to be formatted, the value
of that property, and the atom formatted according to C<format_atom>,
respectively.)

If no format string is supplied in a given format atom, C<%s> is used.

If a format atom C<$value>'s value does not start with a C<$> character, it is
swapped with the value of the prop C<$value> (or the string "(no value)".

All values are filtered through the function C<atom_value>.

=cut

sub _parse_format_summary {
    my $self   = shift;

    my $props = $self->get_props;

    my @out;
    for my $atom ($self->_atomize_summary_format) {
        my %atom_data;
        my ($format, $prop, $value, $color);

        if ($atom =~ /,/) {
            ($format, $prop, $color) = split /,/, $atom;

            $value = $prop;

            unless ($value =~ /^\$/) {
                $value = $props->{$value}
                      || "-"
            }

        } else {
            $format = '%s';
            $prop = $value = $atom;
        }

        my $atom_value = $self->atom_value($value);
        push @out, {
            format    => $format,
            prop      => $prop,
            value     => $atom_value,
            formatted => $self->format_atom( $format, $atom_value, $color ),
        };
    }
    return @out;
}

=head2 format_summary

Returns a formatted string that is the summary for the record. In an
array context, returns a list of

=cut

sub format_summary {
    my $self = shift;

    my @out = $self->_summary_format ?  $self->_parse_format_summary
                                     : $self->_format_all_props_raw;
    return @out if wantarray;
    return join ' ', map { $_->{formatted} } @out;
}

sub _format_all_props_raw {
    my $self  = shift;
    my $props = $self->get_props;

    my @out;

    push @out,
        {
        prop      => 'uuid',
        value     => $self->uuid,
        format    => '%s',
        formatted => "'uuid': '" . $self->uuid . "'"
        };
    push @out, {
        prop      => 'luid',
        value     => $self->luid,
        format    => '%s',
        formatted => "'luid': '"
            . $self->luid . "'"

    };

    for my $prop ( keys %$props ) {
        push @out,
            {
            prop      => $prop,
            value     => $props->{$prop},
            format    => '%s',
            formatted => "'$prop': '" . $props->{$prop} . "'"
            };
    }
    return @out;
}


=head2 atom_value $value_in

Takes an input value from a summary format atom and returns either its
output value or itself (because it is a property and its value should be
retrieved from the props attribute instead).

For example, an input value of "$uuid" would return the record object's
C<uuid> field.

=cut

sub atom_value {
    my $self     = shift;
    my $value_in = shift || '';

    if ($value_in =~ /^\$[gu]uid/) {
        return $self->uuid;
    } elsif ($value_in eq '$luid') {
        return $self->luid;
    }

    return $value_in;
}

=head2 format_atom $string => $value

Takes a format string / value pair and returns a formatted string for printing.
Dies with a message if there's an error in the format string that sprintf warn()s on.

=cut

sub format_atom {
    my ($self, $string, $value, $color) = @_;

    my $formatted_atom;
    eval {
        use warnings FATAL => 'all';    # sprintf only warns on errors
        $formatted_atom = sprintf($string, $self->atom_value($value));
    };
    if ( $@ ) {
        chomp $@;
        die "Error: cannot format value '".$self->atom_value($value)
            ."' using atom '".$string."' in '".$self->type."' summary format\n\n"
            ."Check that the ".$self->type.".summary-format config variable in your config\n"
            ."file is valid. If this variable is not set, this is a bug in the default\n"
            ."summary format for this ticket type.\n\n"
            ."The error encountered was:\n\n'" . $@ . "'\n";
    }
    return $color ? colored($formatted_atom, $color) : $formatted_atom;
}

=head2 find_or_create_luid

Finds the luid for the records uuid, or creates a new one. Returns the luid.

=cut

sub find_or_create_luid {
    my $self = shift;
    my $luid = $self->handle->find_or_create_luid( uuid => $self->uuid );
    $self->luid($luid);
    return $luid;
}

=head2 history_as_string

Returns this record's changesets as a single string.

=cut

sub history_as_string {
    my $self = shift;
    my $out ='';
    for my $changeset ($self->changesets) {
        $out .= $changeset->as_string(change_filter => sub {
            shift->record_uuid eq $self->uuid
        });
    }

    return $out;
}

=head2 record_reference_methods

Returns a list of method names that refer to other individual records

=cut

sub record_reference_methods {
    my $self = shift;
    my $class = blessed($self) || $self;
    my %accessors = %{ $self->REFERENCES->{$class} || {} };

    return grep { $accessors{$_}{arity} eq 'record' }
           keys %accessors;
}

=head2 collection_reference_methods

Returns a list of method names that refer to collections

=cut

sub collection_reference_methods {
    my $self = shift;
    my $class = blessed($self) || $self;
    my %accessors = %{ $self->REFERENCES->{$class} || {} };

    return grep { $accessors{$_}{arity} eq 'collection' }
           keys %accessors;
}

__PACKAGE__->meta->make_immutable;
no Any::Moose;
1;
