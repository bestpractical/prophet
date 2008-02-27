use warnings;
use strict;

package Prophet::Collection;
use Params::Validate;
use base qw/Class::Accessor/;
__PACKAGE__->mk_accessors(qw'handle type');
use Prophet::Record;


sub new {
    my $class = shift;
    my $self = {};
    bless $self, $class;
    my %args = validate(@_, { handle => 1, type => 1});
    $self->$_($args{$_}) for (keys %args);
    return $self;
}


sub matching {
    my $self = shift;
    my $coderef = shift;

    # find all items,
    my $nodes = $self->handle->current_root->dir_entries($self->handle->db_root.'/'.$self->type.'/');
    # run coderef against each item;
    # if it matches, add it to _items
    foreach my $key (keys %$nodes) {
        my $record = Prophet::Record->new(handle => $self->handle, type => $self->type);
        $record->load(uuid => $key);
        if($coderef->($record)) {
            push @{$self->{_items}}, $record;
        }
    
    }


    #return a count of items found


}

sub as_array_ref {
    my $self = shift;
    return $self->{_items}||[];

}


1;
