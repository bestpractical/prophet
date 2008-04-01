use warnings;
use strict;


package Prophet::Test::Participant;
use base qw/Class::Accessor/;
__PACKAGE__->mk_accessors(qw/name/);
use Prophet::Test;


sub new {

    my $self = shift->SUPER::new(@_);
    $self->_setup();
    
}

sub _setup {
    my $self = shift;
    as_user($self->name, sub { run_ok('prophet-node-search', [qw(--type Bug --regex .)])});


}




sub create_random_record {}
sub update_random_record {}
sub sync_from_random_peer {}
sub sync_from_all_peers {}
sub dump_state {}
sub dump_history {}

1;