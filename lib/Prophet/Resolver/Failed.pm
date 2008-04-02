use warnings;
use strict;

package Prophet::Resolver::Failed;
use base qw/Prophet::Resolver/;

sub run {
    die "The resolution was not resolved. Sorry dude. (Once Prophet works, you should NEVER see this message)";
}

1;
