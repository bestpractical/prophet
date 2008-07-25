package Prophet::CLI::Command::Search;
use Moose;
extends 'Prophet::CLI::Command';
with 'Prophet::CLI::RecordCommand';
with 'Prophet::CLI::CollectionCommand';

has '+uuid' => (
    required => 0,
);

sub get_search_callback {
    my $self = shift;

    if ( my $regex = $self->arg('regex') ) {
            return sub {
                my $item  = shift;
                my $props = $item->get_props;
                map { return 1 if $props->{$_} =~ $regex } keys %$props;
                return 0;
            }
    } elsif (scalar $self->prop_names > 0) {
        my %prop_checks;
        for my $check ($self->prop_set) {
            push @{ $prop_checks{ $check->{name} } }, $check;
        }

        return sub {
            my $item = shift;
            my $props = $item->get_props;

            for my $prop (keys %prop_checks) {
                my $got = $props->{$prop};
                my $ok = 0;
                for my $check (@{ $prop_checks{$prop} }) {
                    $ok = 1
                        if $self->cmp_ok($check->{value}, $check->{cmp}, $got);
                }
                return 0 if !$ok;
            }

            return 1;
        };
    } else {
        return sub {1}
    }
}

sub cmp_ok {
    my $self = shift;
    my ($expected, $cmp, $got) = @_;

    if ($cmp eq '=') {
        return 0 if not defined $got;
        return 0 unless $got eq $expected;
    }
    elsif ($cmp eq '=~') {
        return 0 if not defined $got;
        return 0 unless $got =~ $expected;
    }
    elsif ($cmp eq '!=' || $cmp eq '<>') {
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

sub display_terminal {
    my $self = shift;
    my $records = shift;

    for ( sort { $a->luid <=> $b->luid } $records->items ) {
            print $_->format_summary . "\n";
    }
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;

