use warnings;
use strict;

package Prophet::ChangeSet;
use Prophet::Change;
use Params::Validate;

use base qw/Class::Accessor/;

__PACKAGE__->mk_accessors(qw/sequence_no source_uuid original_source_uuid original_sequence_no/);

sub add_change {
    my $self = shift;
    my %args = validate( @_, { change => 1 } );
    push @{ $self->{changes} }, $args{change};

}

sub changes {
    my $self = shift;
    return @{ $self->{'changes'} || [] };
}

1;
