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

    my $display_method = $self->has_arg('html')
                       ? 'display_html'
                       : 'display_terminal';
    $self->$display_method($records);
}

# XXX: this should go away once we have publish-as-html
sub display_html {
    my $self = shift;
    my $records = shift;

    require Prophet::Server::View;
    Template::Declare->init(roots => ['Prophet::Server::View']);
    print Template::Declare->show('record_table' => $records);
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

