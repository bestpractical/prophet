use warnings;
use strict;

package Prophet::Change;
use base qw/Class::Accessor/;

use Prophet::PropChange;

use Params::Validate;
__PACKAGE__->mk_accessors(qw/node_type node_uuid change_type/);

sub add_prop_change {
    my $self = shift;
    my %args = validate(@_, { name => 1, old => 0, new => 0 } );
    my $change = Prophet::PropChange->new();
    $change->name($args{'name'});
    $change->old_value($args{'old'});
    $change->new_value($args{'new'});

    push @{$self->{prop_changes}}, $change;


}


1;
