package Prophet::Record;
use Moose;
use MooseX::ClassAttribute;
use Params::Validate;
use Data::UUID;
use Prophet::App; # for require_module. Kinda hacky

use constant collection_class => 'Prophet::Collection';

=head1 NAME

Prophet::Record

=head1 DESCRIPTION

This class represents a base class for any record in a Prophet database.

=cut

has app_handle => (
    isa => 'Maybe[Prophet::App]',
    is       => 'rw',
    required => 0,
);

has handle => (
    is       => 'rw',
    required => 1,
);

has type => (
    is        => 'rw',
    isa       => 'Str',
    required  => 1,
    predicate => 'has_type',
    default   => sub { undef}
);

has uuid => (
    is      => 'rw',
    isa     => 'Str',
    trigger => sub {
        my $self = shift;
        $self->find_or_create_luid;
    },
);

has luid => (
    is  => 'rw',
    isa => 'Str',
);

class_has REFERENCES => (
    metaclass => 'Collection::Hash',
    is        => 'rw',
    isa       => 'HashRef',
    default   => sub { {} },
    provides  => {
        keys => 'reference_methods',
    },
    documentation => 'A hash of accessor_name => collection_class references.',
);

class_has PROPERTIES => (
    is      => 'rw',
    isa     => 'HashRef',
    default => sub { {} },
    documentation => 'A hash of properties that a record class declares.',
);

my $UUIDGEN = Data::UUID->new();

=head1 METHODS

=head2 new  { handle => Prophet::Replica, type => $type }

Instantiates a new, empty L<Prophet::Record/> of type $type.

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
            type       => $collection_class->record_class->type,
        );
        $collection->matching( sub { ($_[0]->prop( $args{by} )||'') eq $self->uuid }
        );
        return $collection;
    };

    # XXX: add validater for $args{by} in $model->record_class

    $class->REFERENCES->{$accessor} = {
        %args,
        type => $collection_class->record_class,
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
            type       => $record_class->type,
        );
        $record->load(uuid => $self->prop($args{by}));
        return $record;
    };

    # XXX: add validater for $args{by} in $model->record_class

    $class->REFERENCES->{$accessor} = {
        %args,
        type => $record_class,
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
    my $uuid = $UUIDGEN->create_str;

    $self->default_props($args{'props'});
    $self->canonicalize_props( $args{'props'} );
    $self->validate_props( $args{'props'} ) or return undef;

    $self->uuid($uuid);

    $self->handle->create_record(
        props => $args{'props'},
        uuid  => $self->uuid,
        type  => $self->type
    );

    return $self->uuid;
}

=head2 load { uuid => $UUID } or { luid => $UUID }

Loads a Prophet record off disk by its uuid or luid.

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
    } else {
        $self->uuid( $args{uuid} );
    }

    return $self->handle->record_exists(
        uuid => $self->uuid,
        type => $self->type
    );
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
        type => $self->type
    );
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
    $self->handle->delete_record( type => $self->type, uuid => $self->uuid );

}

=head2 changesets

Returns an ordered list of changeset objects for all changesets containing
changes to the record specified by this record object.

Note that changesets may include changes to other records.

=cut

sub changesets {
    my $self = shift;
    return $self->handle->changesets_for_record(
        uuid => $self->uuid,
        type => $self->type,
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
            $sub->( $self, props => $props, errors => $errors ) || push @errors,
                "Validation error for '$key': " . ( $errors->{$key} || '' );
        }
    }
    if (@errors) {
        die join( '', @errors )."\n";
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
        if ( my $sub = $self->can( 'canonicalize_prop_' . $key ) ) {
            $sub->( $self, props => $props, errors => $errors );
        }
    }
    return 1;
}

=head2 default_props $props_ref

Takes a reference to a hash of props and looks up the defaults for those
props, if they exist (by way of C<default_prop_$prop> routines). Sets the
values of the props in the hash to the defaults.

=cut

sub default_props {
    my $self   = shift;
    my $props  = shift;

    my @methods = grep { $_->{name} =~ /^default_prop_/ } $self->meta->compute_all_applicable_methods;

    for my $method_data (@methods) {
        my ($key) = $method_data->{name} =~ /^default_prop_(.+)$/;
        my $sub   = $method_data->{code};

        $props->{$key} = $sub->( $self, props => $props)
            if !defined($props->{$key});
    }

    return 1;
}

=head2 default_prop_creator

Default the creator of every record to the changeset_creator @ replica uuid

=cut

sub default_prop_creator {
    my $self = shift;

    return sprintf '%s@%s',
        $self->handle->changeset_creator,
        $self->handle->uuid;
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

sub _default_summary_format { 'No summary format defined for this record type' }

=head2 _summary_format

Tries to find the summary format for the record type. Returns
L<_default_summary_format> if nothing better can be found.

=cut

sub _summary_format {
    my $self = shift;
    return $self->app_handle->config->get('summary_format_'.$self->type)
        || $self->app_handle->config->get('default_summary_format')
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
    return split /\s*\|\s*/, $format;
}

=head2 _parse_summary_format

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
    foreach my $atom ($self->_atomize_summary_format) {
        my %atom_data;
        my ($format, $prop, $value);

        if ($atom =~ /,/) {
            ($format, $prop) = split /,/, $atom;

            $value = $prop;

            unless ($value =~ /^\$/) {
                $value = $props->{$value}
                      || "(no $value)"
            }

        } else {
            $format = '%s';
            $prop = $value = $atom;
        }

        @atom_data{'format', 'prop'} = ($format, $prop);
        $atom_data{value} = $self->atom_value($value);
        $atom_data{formatted} = $self->format_atom($format => $atom_data{value});

        push @out, \%atom_data;
    }

    return @out;
}

=head2 format_summary

Returns a formatted string that is the summary for the record. In an
array context, returns a list of

=cut

sub format_summary {
    my $self = shift;

    my @out = $self->_parse_format_summary;
    return @out if wantarray;
    return join ' ', map { $_->{formatted} } @out;
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
    my $value_in = shift;

    if ($value_in =~ /^\$[gu]uid/) {
        return $self->uuid;
    } elsif ($value_in eq '$luid') {
        return $self->luid;
    }

    return $value_in;
}

=head2 format_atom $string => $value

Takes a format string / value pair and returns a formatted string for printing.

=cut

sub format_atom {
    my $self = shift;
    my $string = shift;
    my $value = shift;
    return sprintf($string, $self->atom_value($value));
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

=head2 colorize $field, $value

Colorizes the given property / value pair according to the field's
own C<color_prop_$field> routine, or else the generic L<color_prop> routine
if a specific routine does not exist.

=cut

sub colorize {
        my $self = shift;
        my ($field, $value) = @_;
        my $colorized_field;
        my $colorized_value;

            if (my $method = $self->can("color_prop_$field")) {
                $colorized_value = $self->$method($value);
            }
            else {
                ($colorized_field, $colorized_value) = $self->color_prop($field, $value);
            }
            return ($colorized_field, $colorized_value)
        }


=head2 color_prop property, value

Colorize the given property and/or value. Return the (property, value) pair.

You should not alter the length of the property/value display. This will mess
up the table display. You should only use coloring escape codes.

=cut

sub color_prop {
    my $self     = shift;
    my $property = shift;
    my $value    = shift;

    return ($property, $value);
}

=head2 history_as_string

Returns this record's changesets as a single string.

=cut

sub history_as_string {
    my $self = shift;
    my $out = "History for record "
            . $self->luid
            . " (" . $self->uuid . ")"
            . "\n\n";

    for my $changeset ($self->changesets) {
        $out .= $changeset->as_string(change_filter => sub {
            shift->record_uuid eq $self->uuid
        });
    }

    return $out;
}

__PACKAGE__->meta->make_immutable;
no Moose;
no MooseX::ClassAttribute;
1;
