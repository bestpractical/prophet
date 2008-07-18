package Prophet::CLI::Command;
use Moose;

has cli => (
    is => 'rw',
    isa => 'Prophet::CLI',
    weak_ref => 1,
    handles => [
        qw/args  set_arg  arg  has_arg  delete_arg/,
        qw/props set_prop prop has_prop delete_prop/,
        'app_handle', 'run_one_command',
    ],
);

sub fatal_error {
    my $self   = shift;
    my $reason = shift;
    die $reason . "\n";

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

=head2 edit_hash hashref -> hashref

Filters the hash through the user's C<$EDITOR> using L<Proc::InvokeEditor>.

No validation is done on the input or output.

=cut

sub edit_hash {
    my $self = shift;
    my $hash = shift;

    my $input = join "\n", map { "$_: $hash->{$_}\n" } keys %$hash;
    my $output = $self->edit_text($input);

    my $filtered = {};
    while ($output =~ m{^(\S+?):\s*(.*)$}mg) {
        $filtered->{$1} = $2;
    }

    return $filtered;
}

=head2 edit_props [arg], defaults -> hashref

Returns a hashref of the command's props mixed in with any default props.
If the "arg" argument is specified, (default "edit", use C<undef> if you only want default arguments), then L</edit_hash> is invoked on the property list.

=cut

sub edit_props {
    my $self = shift;
    my $arg  = shift || 'edit';

    my %props;
    if (@_ == 1) {
        %props = (%{ $_[0] }, %{ $self->props });
    }
    else {
        %props = (@_, %{ $self->props });
    }

    if ($self->has_arg($arg)) {
        return $self->edit_hash(\%props);
    }

    return \%props;
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;

