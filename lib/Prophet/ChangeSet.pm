package Prophet::ChangeSet;
use Moose;
use MooseX::AttributeHelpers;
use Prophet::Change;
use Params::Validate;

has sequence_no => (
    is => 'rw',
);

has source_uuid => (
    is => 'rw',
);

has original_source_uuid => (
    is => 'rw',
);

has original_sequence_no => (
    is => 'rw',
);

has is_nullification => (
    is => 'rw',
);

has is_resolution => (
    is => 'rw',
);

has changes => (
    metaclass  => 'Collection::Array',
    is         => 'rw',
    isa        => 'ArrayRef[Prophet::Change]',
    auto_deref => 1,
    default    => sub { [] },
    provides   => {
        push   => '_add_change',
    },
);

=head1 NAME

Prophet::ChangeSet

=head1 DESCRIPTION

This class represents a single, atomic Prophet database update. It tracks some metadata about the changeset it self and contains a list of L<Prophet::Change> entries which describe the actual records created, updated and deleted.

=cut

=head1 METHODS

=cut

=head2 new

Instantiate a new, empty L<Prophet::ChangeSet> object.

=cut

=head2 sequence_no

The changeset's sequence number (In subversion terms, revision #) on the replica sending us the changeset

=head2 source_uuid

The uuid of the replica sending us the change

=head2 original_source_uuid

The uuid of the replica where the change was authored

=head2 original_sequence_no

The changeset's sequence number (In subversion terms, revision #) on the replica where the change was originally created

=head2 is_nullification

Currently unused

=head2 is_resolution

Currently unused

=cut

=head2 add_change { change => L<Prophet::Change> }

Add a new change, L<$args{'change'}> to this changeset.

=cut

sub add_change {
    my $self = shift;
    my %args = validate( @_, { change => { isa => 'Prophet::Change' } } );
    $self->_add_change($args{change});

}

=head2 changes

Return an array of all the changes in the current changeset.

=cut

=head2 is_empty

Returns true if this changeset has no changes

=cut

sub is_empty {
    my $self = shift;
    return @{ $self->changes } ? 0 : 1;
}

our @SERIALIZE_PROPS
    = (qw(sequence_no source_uuid original_source_uuid original_sequence_no is_nullification is_resolution));

sub as_hash {
    my $self = shift;
    my $as_hash = { map { $_ => $self->$_() } @SERIALIZE_PROPS };

    for my $change ( $self->changes ) {

        $as_hash->{changes}->{ $change->record_uuid } = $change->as_hash;
    }
    return $as_hash;
}

sub new_from_hashref {
    my $class   = shift;
    my $hashref = shift;
    my $self    = $class->new( { map { $_ => $hashref->{$_} } @SERIALIZE_PROPS } );

    foreach my $change ( keys %{ $hashref->{changes} } ) {
        $self->add_change( change => Prophet::Change->new_from_hashref( $change => $hashref->{changes}->{$change} ) );
    }
    return $self;
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;
