package Prophet::ChangeSet;
use Moose;
use MooseX::AttributeHelpers;
use Prophet::Change;
use Params::Validate;

has creator => (
    is  => 'rw',
    isa => 'Maybe[Str]',
);

has created => (
    is      => 'rw',
    isa     => 'Maybe[Str]',
    default => sub {
        my ($sec, $min, $hour, $day, $month, $year) = gmtime;
        $year += 1900;
        $month++;
        return sprintf '%04d-%02d-%02d %02d:%02d:%02d',
            $year, $month, $day,
            $hour, $min, $sec;
    },
);

has source_uuid => (
    is  => 'rw',
    isa => 'Str',
);

has sequence_no => (
    is  => 'rw',
    isa => 'Maybe[Int]',
);

has original_source_uuid => (
    is  => 'rw',
    isa => 'Str',
);

has original_sequence_no => (
    is  => 'rw',
    isa => 'Maybe[Int]',
);

has is_nullification => (
    is  => 'rw',
    isa => 'Bool',
);

has is_resolution => (
    is  => 'rw',
    isa => 'Bool',
);

has changes => (
    metaclass  => 'Collection::Array',
    is         => 'rw',
    isa        => 'ArrayRef[Prophet::Change]',
    auto_deref => 1,
    default    => sub { [] },
    provides   => {
        push   => '_add_change',
        count  => 'has_changes',
    },
);

=head1 NAME

Prophet::ChangeSet

=head1 DESCRIPTION

This class represents a single, atomic Prophet database update. It tracks some
metadata about the changeset itself and contains a list of L<Prophet::Change>
entries which describe the actual records created, updated and deleted.

=head1 METHODS

=head2 new

Instantiate a new, empty L<Prophet::ChangeSet> object.

=head2 creator

A string representing who created this changeset.

=head2 created

A string representing the ISO 8601 date and time when this changeset
was created (UTC).

=head2 sequence_no

The changeset's sequence number (in subversion terms, revision #) on the
replica sending us the changeset.

=head2 source_uuid

The uuid of the replica sending us the change.

=head2 original_source_uuid

The uuid of the replica where the change was authored.

=head2 original_sequence_no

The changeset's sequence number (in subversion terms, revision #) on the
replica where the change was originally created.

=head2 is_nullification

A boolean value specifying whether this is a nullification changeset or not.

=head2 is_resolution

A boolean value specifying whether this is a conflict resolution changeset
or not.

=head2 changes

Returns an array of all the changes in the current changeset.

=head2 has_changes

Returns true if this changeset has any changes.

=head2 add_change { change => L<Prophet::Change> }

Adds a new change, L<$args{'change'}> to this changeset.

=cut

sub add_change {
    my $self = shift;
    my %args = validate( @_, { change => { isa => 'Prophet::Change' } } );
    $self->_add_change($args{change});

}

our @SERIALIZE_PROPS
    = (qw(creator created sequence_no source_uuid original_source_uuid original_sequence_no is_nullification is_resolution));

=head2 as_hash

Returns a reference to a representation of this changeset as a hash, containing
all the properties in the package variable C<@SERIALIZE_PROPS>, as well as a
C<changes> key containing hash representations of each change in the changeset,
keyed on UUID.

=cut

sub as_hash {
    my $self = shift;
    my $as_hash = { map { $_ => $self->$_() } @SERIALIZE_PROPS };

    $as_hash->{'changes'} = [ map $_->as_hash, $self->changes ];

    return $as_hash;
}

=head2 new_from_hashref HASHREF

Takes a reference to a hash representation of a changeset (such as is
returned by L</as_hash> or serialized json) and returns a new
Prophet::ChangeSet representation of it.

Should be invoked as a class method, not an object method.

For example:
C<Prophet::ChangeSet-E<gt>new_from_hashref($ref_to_changeset_hash)>

=cut

sub new_from_hashref {
    my $class   = shift;
    my $hashref = shift;
    my $self    = $class->new( { map { $_ => $hashref->{$_} } @SERIALIZE_PROPS } );

    for my $change ( @{ $hashref->{changes} } ) {
        $self->add_change( change => Prophet::Change->new_from_hashref( $change->{'record_uuid'} => $change ) );
    }
    return $self;
}

=head2 as_string ARGS

Returns a single string representing the changes in this changeset.

If C<$args{header_callback}> is defined, the string returned from passing
C<$self> to the callback is prepended to the changeset string before it is
returned (instead of L</description_as_string>).

If C<$args{skip_empty}> is defined, an empty string is returned if the
changeset contains no changes.

The argument C<change_filter> can be used to filter certain changes from
the string representation; the function is passed a change and should return
false if that change should be skipped.

The C<change_header> argument, if present, is passed to
C<$change-E<gt>to_string> when individual changes are converted to strings.

=cut

sub as_string {
    my $self = shift;
    my %args = validate(
        @_,
        {   change_filter => 0,
            change_header => 0,
            header_callback => 0,
            skip_empty => 0
        }
    );

    my $body = '';

    for my $change ( $self->changes ) {
        next if $args{change_filter} && !$args{change_filter}->($change);
        $body .= $change->as_string( header_callback => $args{change_header} ) || next;
        $body .= "\n";
    }

    return '' if !$body && $args{'skip_empty'};

    my $header  = $args{header_callback} ? $args{header_callback}->($self) :  $self->description_as_string;
    my $out  = $header ."\n".$body."\n";
    return $out;
}

=head2 description_as_change

Returns a string representing a description of this string.

=cut

sub description_as_string {
    my $self = shift;
     sprintf "Change %d by %s at %s\n\t\t\t\t\(%d@%s)\n\n",
        $self->sequence_no,
        ( $self->creator || '(unknown)' ),
        $self->created,
        $self->original_sequence_no,
        $self->original_source_uuid;
    }
__PACKAGE__->meta->make_immutable;
no Moose;

1;
