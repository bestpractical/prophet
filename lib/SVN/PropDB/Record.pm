
use warnings;
use strict;
package SVN::PropDB::Record;
use Params::Validate;
use base qw'Class::Accessor';
__PACKAGE__->mk_accessors(qw'handle props uuid type');
my $UUIDGEN = Data::UUID->new();

sub new {
    my $class = shift;
    my $self = {};
    bless $self, $class;
    my %args = validate(@_, { handle => 1, type => 1});
    $self->$_($args{$_}) for keys(%args);
    return $self;
}

sub create {
    my $self = shift;
    my %args = validate(@_, {  props => 1});

    $self->uuid($UUIDGEN->create_str);


    $self->_canonicalize_props($args{'props'});
    $self->_validate_props($args{'props'}) || return undef;

    $self->handle->create_node( props => $args{'props'}, uuid => $self->uuid, type => $self->type);

    return $self->uuid;
}





sub load {
    my $self = shift;
    my %args = validate(@_, { uuid => 1});
    $self->uuid($args{uuid});

}

sub set_prop {
    my $self = shift;
    my %args = validate(@_, { name => 1, value => 1});

    my $props = { $args{'name'} => $args{'value'}};

    $self->_canonicalize_props($props);
    $self->_validate_props($props) || return undef;
    $self->handle->set_node_props(type => $self->type, uuid => $self->uuid, props => $props );
}

sub get_props {
    my $self = shift;
    return $self->handle->get_node_props(uuid => $self->uuid, type => $self->type);
}

sub prop {
    my $self = shift;
    my $prop = shift;
    return $self->get_props->{$prop};
}


sub delete_prop {
    my $self = shift;
    my %args = validate(@_, { name => 1});
    $self->handle->delete_node_prop(uuid => $self->uuid, name => $args{'name'});
}

sub delete {
    my $self = shift;
    $self->handle->delete_node(type => $self->type, uuid => $self->uuid);

}

sub _validate_props {
    my $self = shift;
    my $props = shift;
    my $errors = {};
    for my $key (keys %$props) {
        if (my $sub = $self->can('validate_'.$key)) { 
            $sub->($self, props => $props, errors => $errors) || return undef;
        }
    }
    return 1;
}


sub _canonicalize_props {
    my $self = shift;
    my $props = shift;
    my $errors = {};
    for my $key (keys %$props) {
        if (my $sub = $self->can('canonicalize_'.$key)) { 
            $sub->($self, props => $props, errors => $errors);
        }
    }
    return 1;
}


1;
