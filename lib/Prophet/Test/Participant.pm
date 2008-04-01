use warnings;
use strict;


package Prophet::Test::Participant;
use base qw/Class::Accessor/;
__PACKAGE__->mk_accessors(qw/name arena/);
use Prophet::Test;
use Scalar::Util qw/weaken/;

sub new {

    my $self = shift->SUPER::new(@_);
    $self->_setup();
    weaken($self->{'arena'});
    return $self;
}

sub _setup {
    my $self = shift;
    as_user($self->name, sub { run_ok('prophet-node-search', [qw(--type Bug --regex .)])});


}

use List::Util qw(shuffle);

my @CHICKEN_DO = qw(create_record delete_record update_record sync_from_peer noop);

sub take_one_step {
    my $self = shift;
    my $action = (shuffle(@CHICKEN_DO))[0];
    $self->$action();


}


sub noop {
    my $self = shift;
    diag($self->name, ' - NOOP');
}
sub delete_record {
    my $self = shift;
    diag($self->name, ' - delete a random record');
   # run_ok('prophet-node-delete');

}
sub create_record {
    my $self = shift;
    diag($self->name, ' - create a record');
    #run_ok('prophet-node-create', [qw(--type Scratch --foo), $self->name. rand(100)]);
}
sub update_record {
    my $self = shift;
    diag($self->name, ' - update a record');

}
sub sync_from_peer {
    my $self = shift;
    my $lucky = (shuffle(@{$self->arena->chickens}))[0];
  
#    my $lucky = shift @peers;
    diag($self->name, ' - sync from a random peer - ' . $lucky->name);


}
sub sync_from_all_peers {}
sub dump_state {}
sub dump_history {}

1;