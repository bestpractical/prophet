package Prophet::CLI::Command::Search;
use Moose;
extends 'Prophet::CLI::Command';
with 'Prophet::CLI::RecordCommand';
has '+uuid' => ( required => 0);

sub get_collection_object {
    my $self = shift;

    my $class = $self->_get_record_class->collection_class;
    Prophet::App->require_module($class);
    my $records = $class->new(
        app_handle => $self->app_handle,
        handle => $self->app_handle->handle,
        type   => $self->type
    );

    return $records;
}

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
        my $expected_props = $self->props;
        return sub {
            my $item = shift;
            my $props = $item->get_props;

            for (keys %$expected_props) {
                return 0 if not defined $props->{$_};
                return 0 unless $props->{$_} eq $expected_props->{$_};
            }

            return 1;
        };
    } else {
        return sub {1}
    }
}
sub run {
    my $self = shift;

    my $records = $self->get_collection_object();
    my $search_cb = $self->get_search_callback();
    $records->matching($search_cb);

    for ( sort { $a->luid <=> $b->luid } $records->items ) {
            print $_->format_summary . "\n";
    }
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;

