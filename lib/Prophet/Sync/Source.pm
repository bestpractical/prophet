use warnings;
use strict;

package Prophet::Sync::Source;
use base qw/Class::Accessor/;
use Params::Validate;


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



sub import_changesets {
    my $self = shift;
    my %args   = validate( @_, { from => 1 } );
    my $source = $args{'from'};

    my $changesets_to_integrate
        = $source->fetch_changesets( after => $self->last_changeset_from_source( $source->uuid ) );

    for my $changeset (@$changesets_to_integrate) {
#     use Data::Dumper;warn Dumper($changeset) if ($DEBUG);
     
       next if ( $self->has_seen_changeset($changeset) );
        if ( $self->changeset_will_conflict($changeset) ) {

            my $conflicts = $self->conflicts_from_changeset($changeset);

            # write out a nullification changeset beforehand,
            # - that way, the source update will apply cleanly
            # Then write out the source changeset
            # Then write out a new changeset which reverts the parts of the source changeset which target should win
        } else {
            $self->integrate_changeset($changeset);
        }

    }
}





1;
