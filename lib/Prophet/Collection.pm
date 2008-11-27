package Prophet::Collection;
use Moose;
use MooseX::AttributeHelpers;
use Params::Validate;
use Prophet::Record;

use overload '@{}' => sub { shift->items }, fallback => 1;
use constant record_class => 'Prophet::Record';

has app_handle => (
    is  => 'rw',
    isa => 'Maybe[Prophet::App]',
    required => 0,
    trigger => sub {
        my ($self, $app) = @_;
        $self->handle($app->handle);
    },
);

has handle => (
    is  => 'rw',
    isa => 'Prophet::Replica',
);

has type => (
    is      => 'rw',
    isa     => 'Str',
    lazy    => 1,
    default => sub {
        my $self = shift;
        $self->record_class->new(app_handle => $self->app_handle)->record_type;
    },
);

has items => (
    metaclass  => 'Collection::Array',
    is         => 'rw',
    isa        => 'ArrayRef[Prophet::Record]',
    default    => sub { [] },
    auto_deref => 1,
    provides   => {
        push   => 'add_item',
        count  => 'count',
    },
);

=head1 NAME

Prophet::Collection

=head1 DESCRIPTION

This class allows the programmer to search for L<Prophet::Record>
objects matching certain criteria and to operate on those records
as a collection.

=head1 METHODS

=head2 new { handle => L<Prophet::Replica>, type => $TYPE }

Instantiate a new, empty L<Prophet::Collection> object to find items of type
C<$TYPE>.

=head2 matching $CODEREF

Find all L<Prophet::Record>s of this collection's C<type> where $CODEREF
returns true.

=cut

sub matching {
    my $self    = shift;
    my $coderef = shift;
    return undef unless $self->handle->type_exists( type => $self->type );
    # find all items,
    Carp::cluck unless defined $self->type;

    my $records = $self->handle->list_records( type => $self->type );

    
    # run coderef against each item;
    # if it matches, add it to items
    for my $key (@$records) {
        my $record = $self->record_class->new( { app_handle => $self->app_handle,  handle => $self->handle, type => $self->type } );
        $record->load( uuid => $key );
        if ( $coderef->($record) ) {
            $self->add_item($record);
        }

    }

    #return a count of items found

}

=head2 items

Returns a reference to an array of all the items found

=head2 add_item

=head2 count

=cut

__PACKAGE__->meta->make_immutable;
no Moose;

1;
