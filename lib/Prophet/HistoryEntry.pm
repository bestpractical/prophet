use warnings;
use strict;

package Prophet::HistoryEntry;

use base qw/Class::Accessor/;
use Params::Validate;

=head1 NAME

Prophet::HistoryEntry

=head1 DESCRIPTION

This class represents an indivdual, local change in the history of a L<Prophet::Replica>.
In the future, this class's representation should be merged with the code we're using for L<Prophet::Sync>


=cut

__PACKAGE__->mk_accessors(qw/handle rev date author msg action props prop_changes copy_from copy_from_rev/);

=head1 METHODS

=head2 new { handle => L<Prophet::Handle> }

Create a new, empty history entry. 


=cut

sub new {
   my $class = shift;
   my $self = {};
   bless $self, $class;


    my   %args = validate( @_, {handle => 1});
    $self->handle($args{'handle'});
    $self->prop_changes({});
   return $self;

}

=head2 rev

The local revision number for this history entry

=head2 date

The date this history entry was recorded. in RFC2445 format

=head2 author

The original author of this commit. Right now, this is a nice, forgable text string. It should likely become an email address or a replica UUID

=head2 msg

The commit message associated with the update

=head2 action

Was a node created, updated or deleted?

XXX TODO FILL IN VALID VALUES


=head2 props

The current value of the record's properties after this update?

=head2 prop_changes

NEEDS DESCRIPTION

=head2 copy_from

unused

=head2 copy_from_rev

unused

=cut

1;
