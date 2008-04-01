use warnings;
use strict;


package Prophet::Test::Arena;
use base qw/Class::Accessor/;


use Acme::MetaSyntactic;
use Prophet::Test;
__PACKAGE__->mk_accessors(qw/chickens/);


sub setup {
    my $self  = shift;
    my $count = shift;
    # create a set of n test participants
        # that should initialize their environments

    my @chickens;

    my $meta = Acme::MetaSyntactic->new();
    
    for my $name ($meta->name(pause_id => $count)) {
        push @chickens,Prophet::Test::Participant->new( { name => $name } );

    }

    $self->chickens(\@chickens);
        
}

sub act_like_chickens {
    # for x rounds, have each participant execute a random action
}

sub sync_all_pairs {
    

}
1;