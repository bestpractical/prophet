use warnings;
use strict;


package Prophet::Test::Arena;
use base qw/Class::Accessor/;
__PACKAGE__->mk_accessors(qw/chickens record_callback history/);

use Prophet::Test::Participant;
use Acme::MetaSyntactic;
use Prophet::Test;
use YAML::Syck ();

sub setup {
    my $self  = shift;
    my $count = shift;
    my @names = ref $count ? @$count : Acme::MetaSyntactic->new->name(pause_id => $count);

    my @chickens = map { Prophet::Test::Participant->new( { name => $_, arena => $self } ) } @names;
    $self->chickens(@chickens);
}

sub run_from_yaml {
    my $self = shift;
    my @c = caller(0);
    no strict 'refs';
    my $fh = *{$c[0].'::DATA'};

    return $self->run_from_yamlfile(@ARGV) unless fileno($fh);

    local $/;
    $self->run_from_data(YAML::Syck::Load( <$fh> ));
}

sub run_from_yamlfile {
    my ($self, $file) = @_;
    $self->run_from_data(YAML::Syck::LoadFile( $file ));
}

sub run_from_data {
    my ($self, $data) = @_;

    Test::More::plan( tests => scalar @{ $data->{recipe}} + scalar @{ $data->{chickens}} );
    my $arena = Prophet::Test::Arena->new(
        { record_callback => sub {
                my ( $name, $action, $args ) = @_;
                return;
            },
        }
    );
    $arena->setup($data->{chickens});

    my $record_map;

    for (@{$data->{recipe}}) {
        my ($name, $action, $args) = @$_;
        my ($chicken) = grep { $_->name eq $name } @{ $arena->chickens };
        if ($args->{record}) {
            $args->{record} = $record_map->{ $args->{record} };
    }
        my $next_result = $args->{result};

        as_user($chicken->name, sub { $chicken->take_one_step($action, $args ) });

        if ($args->{result}) {
            $record_map->{ $next_result } = $args->{result};
        }
    }
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
           as_user($a->name, sub {$a->sync_from_peer({ from => $b->name }) });
        $seen_pairs{$a->name."-".$b->name} =1;
    }

    }
    

}

sub record {
    my ($self, $name, $action, $args) = @_;
    my $stored = { %$args };
    if ( my $record = $stored->{record} ) {
        $stored->{record} = $self->{record_map}{ $record };
    }
    elsif (my $result = $stored->{result}) {
        $stored->{result} = $self->{record_map}{ $result } =
            ++$self->{record_cnt};
    }
    return $self->record_callback->($name, $action, $args)
        if $self->record_callback;

    # XXX: move to some kind of recorder class and make use of callback
    push @{$self->{history} ||= []}, [$name, $action, $stored];
}

1;
