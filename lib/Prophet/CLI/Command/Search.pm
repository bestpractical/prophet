package Prophet::CLI::Command::Search;
use Moose;
extends 'Prophet::CLI::Command';
with 'Prophet::CLI::RecordCommand';
with 'Prophet::CLI::CollectionCommand';

has '+uuid' => (
    required => 0,
);

has 'sort_routine' => (
    is => 'rw',
    isa => 'CodeRef',
    required => 0,
    # default subs are executed immediately, hence the weird syntax for coderefs
    default => sub { sub {
                my $records = shift;
            return (sort { $a->luid <=> $b->luid } @$records);
        } },
    documentation => 'A subroutine which takes a hashref to a list of records and returns them sorted in some way.',
);

sub default_match { 1 }

sub get_search_callback {
    my $self = shift;

    my %prop_checks;
    for my $check ($self->prop_set) {
        push @{ $prop_checks{ $check->{prop} } }, $check;
    }

    my $regex = $self->arg('regex');

    return sub {
        my $item = shift;
        my $props = $item->get_props;
        my $did_limit = 0;

        if ($self->prop_names > 0) {
            $did_limit = 1;

            for my $prop (keys %prop_checks) {
                my $got = $props->{$prop};
                my $ok = 0;
                for my $check (@{ $prop_checks{$prop} }) {
                    $ok = 1
                        if $self->cmp_ok($check->{value}, $check->{cmp}, $got);
                }
                return 0 if !$ok;
            }
        }

        # if they specify a regex, it must match
        if ($regex) {
            $did_limit = 1;
            my $ok = 0;

            for (values %$props) {
                if (/$regex/) {
                    $ok = 1;
                    last;
                }
            }
            return 0 if !$ok;
        }

        return $self->default_match($item) if !$did_limit;

        return 1;
    };
}

sub cmp_ok {
    my $self = shift;
    my ($expected, $cmp, $got) = @_;

    $got = '' if !defined($got); # avoid undef warnings

    if ($cmp eq '=') {
        return 0 unless $got eq $expected;
    }
    elsif ($cmp eq '=~') {
        return 0 unless $got =~ $expected;
    }
    elsif ($cmp eq '!=' || $cmp eq '<>' || $cmp eq 'ne') {
        return 0 if $got eq $expected;
    }
    elsif ($cmp eq '!~') {
        return 0 if $got =~ $expected;
    }

    return 1;
}

sub run {
    my $self = shift;

    my $records = $self->get_collection_object();
    my $search_cb = $self->get_search_callback();
    $records->matching($search_cb);

    $self->display_terminal($records);
}

=head2 display_terminal $records

Takes a collection of records, sorts it according to C<$sort_routine>,
and then prints it to standard output using L<Prophet::Record->format_summary>
as the format.

=cut

sub display_terminal {
    my $self = shift;
    my $records = shift;

    my $items = $records->items;
    for ( $self->sort_routine->( $items) ) {
            print $_->format_summary . "\n";
    }
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;

