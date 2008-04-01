use warnings;
use strict;


package Prophet::Test::Arena;
use base qw/Class::Accessor/;
__PACKAGE__->mk_accessors(qw/chickens/);

use Acme::MetaSyntactic;
use Prophet::Test;

sub setup {
    my $self  = shift;
    my $count = shift;
    # create a set of n test participants
        # that should initialize their environments

    my @chickens;

    my $meta = Acme::MetaSyntactic->new();
    
    for my $name ($meta->name(pause_id => $count)) {
        push @chickens,Prophet::Test::Participant->new( { name => $name, arena => $self } );

    }
    $self->chickens(@chickens);
        
}

sub step {
    my $self = shift;
    my $step_name = shift || undef;
    for my $chicken (@{$self->chickens}) {
        as_user($chicken->name, sub {$chicken->take_one_step($step_name)});
    }

    # for x rounds, have each participant execute a random action
}

sub dump_state {
    my $self = shift;
    my %state;
    for my $chicken ( @{ $self->chickens } ) {
        $state{ $chicken->name } = as_user( $chicken->name, sub { $chicken->dump_state } );
    }
    return \%state;
}


use List::Util qw/shuffle/;
sub sync_all_pairs {
    my $self = shift;

    diag("now syncing all pairs");

    my @chickens_a = shuffle @{$self->chickens};
    my @chickens_b = shuffle @{$self->chickens};
 
    my %seen_pairs;

    foreach my $a (@chickens_a) {
        foreach my $b (@chickens_b) { 
        next if $a->name eq $b->name;
        next if ($seen_pairs{$b->name."-".$a->name});
        diag($a->name, $b->name);
           as_user($a->name, sub {$a->sync_from_peer($b) });
        $seen_pairs{$a->name."-".$b->name} =1;
    }

    }
    

}

sub record {
    my ($self, $name, $action, @args) = @_;
    push @{$self->{history} ||= []}, [$name, $action, @args];
}

1;
