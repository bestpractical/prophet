package Prophet::Record;
use Moose;
use MooseX::ClassAttribute;
use Params::Validate;
use Data::UUID;
use List::MoreUtils qw/uniq/;
use Prophet::App; # for require_module. Kinda hacky

use constant collection_class => 'Prophet::Collection';

=head1 NAME

Prophet::Record

=head1 DESCRIPTION

This class represents a base class for any record in a Prophet database

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
    default   => sub {
        my $self = shift;
        $self->record_type;
    },
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
    is      => 'rw',
    isa     => 'HashRef',
    default => sub { {} },
);

class_has PROPERTIES => (
    is      => 'rw',
    isa     => 'HashRef',
    default => sub { {} },
);

sub declared_props {
    return sort keys %{ $_[0]->PROPERTIES };
}

my $UUIDGEN = Data::UUID->new();

sub record_type { $_[0]->has_type ? $_[0]->type : undef }

=head1 METHODS

=head2 new  { handle => Prophet::Replica, type => $type }

Instantiates a new, empty L<Prophet::Record/> of type $type.

=cut

=head2 register_reference

=cut

sub register_reference {
    my ( $class, $accessor, $foreign_class, @args ) = @_;
    $foreign_class->require();
    if ( $foreign_class->isa('Prophet::Collection') ) {
        return $class->register_collection_reference(
            $accessor => $foreign_class,
            @args
        );
    } elsif ( $foreign_class->isa('Prophet::Record') ) {

    } else {
        die "Your foreign class ($foreign_class) must be a subclass of Prophet::Record or Prophet::Collection";
    }

}

=head2 register_collection_reference $accessor, $collection_class, by => $key_in_model

Registers and create accessor in current class the associated
collection C<$collection_class>, which refers to the current class by
$key_in_model in the model class of $collection_class.

=cut

sub register_collection_reference {
    my ( $class, $accessor, $collection_class, @args ) = @_;
    my %args = validate( @args, { by => 1 } );
    no strict 'refs';

    Prophet::App->require_module( $collection_class->record_class );

    *{ $class . "::$accessor" } = sub {
        my $self       = shift;
        my $collection = $collection_class->new(
            handle => $self->handle,
            type   => $collection_class->record_class->record_type
        );
        $collection->matching( sub { ($_[0]->prop( $args{by} )||'') eq $self->uuid }
        );
        return $collection;
    };

    # XXX: add validater for $args{by} in $model->record_class

    $class->REFERENCES->{$accessor}
        = { %args, type => $collection_class->record_class };
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

On success, returns ____

=cut

sub set_props {
    my $self = shift;
    my %args = validate( @_, { props => 1 } );

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
    return $self->handle->get_record_props(
        uuid => $self->uuid,
        type => $self->type
    );
}

=head2 prop $name

Returns the current value of the property C<$name> for this record. 
(This is a convenience method wrapped around L</get_props>.

=cut

sub prop {
    my $self = shift;
    my $prop = shift;
    return $self->get_props->{$prop};
}

=head2 delete_prop { name => $name }

Deletes the current value for the property $name. 

TODO: how is this different than setting it to an empty value?

=cut

sub delete_prop {
    my $self = shift;
    my %args = validate( @_, { name => 1 } );
    $self->handle->delete_record_prop(
        uuid => $self->uuid,
        name => $args{'name'}
    );
}

=head2 delete

Deletes this record from the database. (Note that it does _not_ purge historical versions of the record)

=cut

sub delete {
    my $self = shift;
    $self->handle->delete_record( type => $self->type, uuid => $self->uuid );

}

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

sub _validate_prop_name {1}

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

=head2 format_summary

returns a formated string that is the summary for the record.

=cut


sub _default_summary_format { 'No summary format defined for this record type' }

sub format_summary {
    my $self   = shift;

    my $configured_format =
         $self->app_handle->config->get('summary_format_'.$self->type) 
         || $self->app_handle->config->get('default_summary_format')
         || $self->_default_summary_format ;
    my $props = $self->get_props;

    my @out;
    foreach my $atom(split(/\s*\|\s*/,$configured_format)) {
            my ($format_string,$prop);
            if ($atom =~ /,/) {
                  ($format_string,$prop) = split(/,/,$atom);
                $prop  = ($props->{$prop} || "(no $prop)") unless ($prop =~ /^\$/);
            } else {
                $format_string = '%s';
                $prop = $atom;
            }
            push @out, $self->format_atom( $format_string => $prop);
    }
    return join(' ', @out);

}

sub format_atom {
    my $self = shift;
    my $string = shift;
    my $value_in = shift;
    my $value;
    if ($value_in =~ /^\$[gu]uid/) {
            $value = $self->uuid;
    } elsif ($value_in eq '$luid') {
            $value = $self->luid;
    } else {
            $value = $value_in;
    }
    return sprintf($string, $value);
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

__PACKAGE__->meta->make_immutable;
no Moose;
no MooseX::ClassAttribute;

1;
