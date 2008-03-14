
use warnings;
use strict;
package Prophet::ConflictingPropChange;
use base qw/Class::Accessor/;

__PACKAGE__->mk_accessors(qw/name source_old_value target_value source_new_value/);

1;
