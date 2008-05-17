package Prophet::Change;
use Moose;
use Moose::Util::TypeConstraints;
use MooseX::AttributeHelpers;
use Prophet::PropChange;
use Params::Validate;

has record_type => (
    is  => 'rw',
    isa => 'Str',
);

has record_uuid => (
    is  => 'rw',
    isa => 'Str',
);

has change_type => (
    is  => 'rw',
    isa => enum([qw/add_file add_dir update_file delete/]),
);

has resolution_cas => (
    is  => 'rw',
    isa => 'Str',
);

has is_resolution => (
    is  => 'rw',
    isa => 'Bool',
);

has prop_changes => (
    metaclass  => 'Collection::Array',
    is         => 'rw',
    isa        => 'ArrayRef[Prophet::PropChange]',
    auto_deref => 1,
    default    => sub { [] },
    provides   => {
        empty => 'has_prop_changes',
        push  => '_add_prop_change',
    },
);

=head1 NAME

Prophet::Change

=head1 DESCRIPTION

This class encapsulates a change to a single record in a Prophet replica.

=head1 METHODS

=head2 record_type

The record type for the record.

=head2 record_uuid

The UUID of the record being changed

=head2 change_type

One of add_file, add_dir, update_file, delete

=head2 prop_changes [\@PROPCHANGES]

Returns a list of L<Prophet::PropChange/> associated with this Change. Takes an optional arrayref to fully replace the set of propcahnges

=cut

=head2 new_from_conflict( $conflict )

=cut

sub new_from_conflict {
    my ( $class, $conflict ) = @_;
    my $self = $class->new(
        {   is_resolution  => 1,
            resolution_cas => $conflict->fingerprint,
            change_type    => $conflict->change_type,
            record_type      => $conflict->record_type,
            record_uuid      => $conflict->record_uuid
        }
    );
    return $self;
}

=head2 add_prop_change { new => __, old => ___, name => ___ }

Adds a new L<Prophet::PropChange> to this L<Prophet::Change>.

Takes a C<name>, and the C<old> and C<new> values.

=cut

sub add_prop_change {
    my $self   = shift;
    my %args   = validate( @_, { name => 1, old => 0, new => 0 } );
    my $change = Prophet::PropChange->new(
        name      => $args{'name'},
        old_value => $args{'old'},
        new_value => $args{'new'},
    );
    $self->_add_prop_change($change);
}

sub as_hash {
    my $self  = shift;
    my $props = {};
    for my $pc ( $self->prop_changes ) {
        $props->{ $pc->name } = { old_value => $pc->old_value, new_value => $pc->new_value };
    }

    return {
        record_type    => $self->record_type,
        change_type  => $self->change_type,
        prop_changes => $props

    };
}

sub new_from_hashref {
    my $class   = shift;
    my $uuid    = shift;
    my $hashref = shift;
    my $self    = $class->new(
        { record_type => $hashref->{'record_type'}, record_uuid => $uuid, change_type => $hashref->{'change_type'} } );
    foreach my $prop ( keys %{ $hashref->{'prop_changes'} } ) {
        $self->add_prop_change(
            name => $prop,
            old  => $hashref->{'prop_changes'}->{$prop}->{'old_value'},
            new  => $hashref->{'prop_changes'}->{$prop}->{'new_value'}
        );
    }
    return $self;
}

__PACKAGE__->meta->make_immutable;
no Moose;
no Moose::Util::TypeConstraints;

1;
