use warnings;
use strict;

package Prophet::Collection;
use Params::Validate;
use base qw/Class::Accessor/;

use overload '@{}' => \&as_array_ref, fallback => 1;

__PACKAGE__->mk_accessors(qw'handle type');
use Prophet::Record;

=head1 NAME

Prophet::Collection

=head1 DESCRIPTION

This class allows the programmer to search for L<Prophet::Record>
objects matching certain criteria and to operate on those records
as a collection.

=head1 METHODS


=head2 new { handle => L<Prophet::Handle>, type => $TYPE }

Instantiate a new, empty L<Prophet::Collection> object to find items of type C<$TYPE>


=cut

sub new {
    my $class = shift;
    my $self  = {};
    bless $self, $class;
    my %args = validate( @_, { handle => 1, type => 1 } );
    $self->$_( $args{$_} ) for ( keys %args );
    return $self;
}

=head2 matching $CODEREF

Find all L<Prophet::Record>s of this collection's C<type> where $CODEREF returns true.

=cut

sub matching {
    my $self    = shift;
    my $coderef = shift;

    return undef unless $self->handle->type_exists( type => $self->type );

    # find all items,
    Carp::cluck unless defined $self->type;
    
    my $nodes = $self->handle->current_root->dir_entries( $self->handle->db_root . '/' . $self->type . '/' );

    # run coderef against each item;
    # if it matches, add it to _items
    foreach my $key ( keys %$nodes ) {
        my $record = Prophet::Record->new( handle => $self->handle, type => $self->type );
        $record->load( uuid => $key );
        if ( $coderef->($record) ) {
            push @{ $self->{_items} }, $record;
        }

    }

    #return a count of items found

}

=head2 as_array_ref

Return the set of L<Prophet::Record>s we've found as an array reference or return an empty array ref if none were found.

=cut

sub as_array_ref {
    my $self = shift;
    return $self->{_items} || [];

}

1;
