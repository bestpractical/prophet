use warnings;
use strict;

package SVN::PropDB::HistoryEntry;

use base qw/Class::Accessor/;
use Params::Validate;


__PACKAGE__->mk_accessors(qw/handle rev date author msg action props prop_changes copy_from copy_from_rev/);


sub new {
   my $class = shift;
   my $self = {};
   bless $self, $class;


    my   %args = validate( @_, {handle => 1});
    $self->handle($args{'handle'});
    $self->prop_changes({});
   return $self;

}
1;
