use warnings;
use strict;

package Prophet::Sync::Source;
use base qw/Class::Accessor/;

=head1 NAME

Prophet::Sync::Source

=head1 DESCRIPTION

A base class for all Prophet sync sources

=cut

=head1 METHODS

=head2 new

Instantiates a new sync source

=cut

sub new {
    my $self = shift->SUPER::new(@_);
    $self->rebless_to_replica_type();
    $self->setup();
    return $self;
}

=head2 rebless_to_replica_type

Reblesses this sync source into the right sort of sync source for whatever kind of replica $self->url points to

TODO: currently knows that we only have SVN replicas


=cut


sub rebless_to_replica_type {
   my $self = shift;
   bless $self, 'Prophet::Sync::Source::SVN';
}


1;
