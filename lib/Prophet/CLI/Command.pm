package Prophet::CLI::Command;
use Moose;

use Params::Validate qw(validate);

has cli => (
    is => 'rw',
    isa => 'Prophet::CLI',
    weak_ref => 1,
    handles => [
        qw/app_handle handle resdb_handle config/,
    ],
);

has context => (
    is => 'rw',
    isa => 'Prophet::CLIContext',
    handles => [ 
        qw/args  set_arg  arg  has_arg  delete_arg  arg_names/,
        qw/props set_prop prop has_prop delete_prop prop_names/,
        'add_to_prop_set', 'prop_set',
    ],

);


sub fatal_error {
    my $self   = shift;
    my $reason = shift;

    # always skip this fatal_error function when generating a stack trace
    local $Carp::CarpLevel = $Carp::CarpLevel + 1;

    die $reason . "\n";
}

=head2 require_uuid

Checks to make sure the uuid attribute is set. Prints an error and dies
if it is not set.

=cut

sub require_uuid {
    my $self    = shift;

    if (!$self->has_uuid) {
        my $type = $self->type;
        my $name = (split /::/, $self->meta->name)[-1];
        die "\u$type \l$name requires a luid or uuid (use --id to specify).\n";
    }
}

=head2 edit_text [text] -> text

Filters the given text through the user's C<$EDITOR> using
L<Proc::InvokeEditor>.

=cut

sub edit_text {
    my $self = shift;
    my $text = shift;

    require Proc::InvokeEditor;
    return scalar Proc::InvokeEditor->edit($text);
}

=head2 edit_hash hash => hashref, ordering => arrayref

Filters the hash through the user's C<$EDITOR> using L<Proc::InvokeEditor>.

No validation is done on the input or output.

If the optional ordering argument is specified, hash keys will be presented
in that order (with unspecified elements following) for edit.

If the record class for the current type defines a C<props_not_to_edit>
routine, those props will not be presented for editing.

False values are not returned unless a prop is removed from the output.

=cut

sub edit_hash {
    my $self = shift;
    validate( @_, { hash => 1, ordering => 0 } );
    my %args = @_;
    my $hash = $args{'hash'};
    my @ordering = @{ $args{'ordering'} || [] };
    my $record = $self->_get_record_object;
    my $do_not_edit = $record->can('props_not_to_edit') ? $record->props_not_to_edit : '';

    if (@ordering) {
        # add any keys not in @ordering to the end of it
        my %keys_in_ordering;
        map { $keys_in_ordering{$_} = 1 if exists($hash->{$_}) } @ordering;
        map { push @ordering, $_ if !exists($keys_in_ordering{$_}) } keys %$hash;
    } else {
        @ordering = sort keys %$hash;
    }

    # filter out props we don't want to present for editing
    @ordering = grep { !/$do_not_edit/ } @ordering;

    my $input = join "\n", map { "$_: $hash->{$_}" } @ordering;

    my $output = $self->edit_text($input);

    die "Aborted.\n" if $input eq $output;

    # parse the output
    my $filtered = {};
    foreach my $line (split "\n", $output) {
        if ($line =~ m/^([^:]+):\s*(.*)$/) {
            my $prop = $1;
            my $val = $2;
            # don't return empty values
            $filtered->{$prop} = $val unless !($val);
        }
    }
    no warnings 'uninitialized';

    # if a key is deleted intentionally, set its value to ''
    foreach my $prop (keys %$hash) {
        if (!exists $filtered->{$prop} and $prop =~ !/$do_not_edit/) {
            $filtered->{$prop} = '';
        }
    }

    # filter out unchanged keys as they clutter changesets if they're set again
    map { delete $filtered->{$_} if $hash->{$_} eq $filtered->{$_} } keys %$filtered;

    return $filtered;
}

=head2 edit_props arg => str, defaults => hashref, ordering => arrayref

Returns a hashref of the command's props mixed in with any default props.
If the "arg" argument is specified, (default "edit", use C<undef> if you only
want default arguments), then L</edit_hash> is invoked on the property list.

If the C<ordering> argument is specified, properties will be presented in that
order (with unspecified props following) if filtered through L</edit_hash>.

=cut

sub edit_props {
    my $self = shift;
    my %args = @_;
    my $arg  = $args{'arg'} || 'edit';
    my $defaults = $args{'defaults'};

    my %props;
    if ($defaults) {
        %props = (%{ $defaults }, %{ $self->props });
    } else {
        %props = %{$self->props};
    }

    if ($self->has_arg($arg)) {
        return $self->edit_hash(hash => \%props, ordering => $args{'ordering'});
    }

    return \%props;
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;

