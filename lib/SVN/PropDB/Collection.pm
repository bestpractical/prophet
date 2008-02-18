use warnings;
use strict;

package SVN::PropDB::Collection;
use Params::Validate;
use base qw/Class::Accessor/;
__PACKAGE__->mk_accessors(qw'handle');
use SVN::PropDB::Record;


sub new {
    my $class = shift;
    my $self = {};
    bless $self, $class;
    my %args = validate(@_, { handle => 1});
    $self->handle($args{'handle'});
    return $self;
}


sub matching {
    my $self = shift;
    my $coderef = shift;

    # find all items,
    my $nodes = $self->handle->current_root->dir_entries('/_propdb','/');
    # run coderef against each item;
    # if it matches, add it to _items
    foreach my $key (keys %$nodes) {
        warn "considering $key";    
        my $record = SVN::PropDB::Record->new(handle => $self->handle);
        $record->load(uuid => $key);
        if($coderef->($record)) {
            push @{$self->{_items}}, $record;
           } else {
            warn "no love!";
        }
    
    }


    #return a count of items found


}

sub as_array_ref {
    my $self = shift;
    return $self->{_items}||[];

}


1;
