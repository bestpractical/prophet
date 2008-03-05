use warnings;
use strict;

package Prophet::ChangeSet;
use Prophet::Change;
use Params::Validate;

use base qw/Class::Accessor/;

__PACKAGE__->mk_accessors(qw/change_uuid source_uuid/);

sub add_change {
    my $self = shift;
    my %args = validate(@_, { change => 1} );
    push @{$self->{changes}}, $args{change};


}

1;
