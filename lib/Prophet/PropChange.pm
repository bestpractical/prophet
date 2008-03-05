use warnings;
use strict;
package Prophet::PropChange;
use base qw/Class::Accessor/;

__PACKAGE__->mk_accessors(qw/name old_value new_value/);


1;
