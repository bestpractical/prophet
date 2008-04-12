use warnings;
use strict;

package Prophet::Record;

=head1 NAME

Prophet::Record

=head1 DESCRIPTION

This class represents a base class for any record in a Prophet database

=cut

use base qw'Class::Accessor Class::Data::Inheritable';

__PACKAGE__->mk_accessors(qw'handle uuid type');
__PACKAGE__->mk_classdata( REFERENCES => {} );
__PACKAGE__->mk_classdata( PROPERTIES => {} );

sub declared_props {
    return sort keys %{ $_[0]->PROPERTIES };
}

use Params::Validate;
use Data::UUID;
use List::MoreUtils qw/uniq/;
my $UUIDGEN = Data::UUID->new();

use constant collection_class => 'Prophet::Collection';

=head1 METHODS

=head2 new  { handle => Prophet::Replica, type => $type }

Instantiates a new, empty L<Prophet::Record/> of type $type.

=cut

sub new {
    my $class = shift;
    my $self  = bless {}, $class;
    my $args  = ref( $_[0] ) ? $_[0] : {@_};
    $args->{type} ||= $class->record_type;
    my %args = validate( @{ [%$args] }, { handle => 1, type => 1 } );
    $self->$_( $args{$_} ) for keys(%args);
    return $self;
}

sub record_type { $_[0]->type }

=head2 register_reference

=cut

sub register_reference {
    my ( $class, $accessor, $foreign_class, @args ) = @_;
    if ( $foreign_class->isa('Prophet::Collection') ) {
        return $class->register_collection_reference(
            $accessor => $foreign_class,
            @args
        );
    } elsif ( $foreign_class->isa('Prophet::Record') ) {

        #        warn "not yet";
    } else {
        die "wtf";
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
    *{ $class . "::$accessor" } = sub {
        my $self = shift;
        my $collection = $collection_class->new( handle => $self->handle, type => $collection_class->record_class );
        $collection->matching( sub { $_[0]->prop( $args{by} ) eq $self->uuid } );
        return $collection;
    };

    # XXX: add validater for $args{by} in $model->record_class

    $class->REFERENCES->{$accessor} = { %args, type => $collection_class->record_class };
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

    $self->canonicalize_props( $args{'props'} );
    $self->validate_props( $args{'props'} ) or return undef;

    $self->uuid($uuid);

    $self->handle->create_node(
        props => $args{'props'},
        uuid  => $self->uuid,
        type  => $self->type
    );

    return $self->uuid;
}

=head2 load { uuid => $UUID }

Loads a Prophet record off disk by its uuid.

=cut

sub load {
    my $self = shift;
    my %args = validate( @_, { uuid => 1 } );
    $self->uuid( $args{uuid} );

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
    $self->validate_props( $args{'props'} );
    $self->handle->set_node_props( type => $self->type, uuid => $self->uuid, props => $args{'props'} );
}

=head2 get_props

Returns a hash of this record's properties as currently set in the database.

=cut

sub get_props {
    my $self = shift;
    return $self->handle->get_node_props( uuid => $self->uuid, type => $self->type );
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
    $self->handle->delete_node_prop( uuid => $self->uuid, name => $args{'name'} );
}

=head2 delete

Deletes this record from the database. (Note that it does _not_ purge historical versions of the record)

=cut

sub delete {
    my $self = shift;
    $self->handle->delete_node( type => $self->type, uuid => $self->uuid );

}

sub validate_props {
    my $self   = shift;
    my $props  = shift;
    my $errors = {};
    for my $key ( uniq( keys %$props, $self->declared_props ) ) {
        return undef unless ( $self->_validate_prop_name($key) );
        if ( my $sub = $self->can( 'validate_prop_' . $key ) ) {
            $sub->( $self, props => $props, errors => $errors ) or die "validation error on $key: $errors->{$key}\n";
        }
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

=head2 format_summary

returns a formated string that is the summary for the record.

=cut

use constant summary_format => '%u';
use constant summary_props  => ();

sub format_summary {
    my $self   = shift;
    my $format = $self->summary_format;
    my $uuid   = $self->uuid;
    $format =~ s/%u/$uuid/g;

    return sprintf( $format, map { $self->prop($_) || "(no $_)" } $self->summary_props );

}

1;
