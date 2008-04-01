use warnings;
use strict;

package Prophet::Sync::Source;
use base qw/Class::Accessor/;
use Params::Validate qw(:all);


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
    my %args   = validate( @_, { from => { isa => 'Prophet::Sync::Source'},
                                 resolver => { optional => 1},
                                 conflict_callback => { optional => 1 } } );
    my $source = $args{'from'};

    my $changesets_to_integrate
        = $source->fetch_changesets( after => $self->last_changeset_from_source( $source->uuid ) );

    for my $changeset (@$changesets_to_integrate) {
    
       next if ( $self->has_seen_changeset($changeset) );
       next if $changeset->is_nullification || $changeset->is_resolution;
        $self->integrate_changeset( changeset => $changeset, conflict_callback => $args{conflict_callback}, resolver => $args{resolver});

    }
}

sub fetch_resolutions {
    my $self = shift;
    my %args   = validate( @_, { from => { isa => 'Prophet::Sync::Source'},
                                 resolver => { optional => 1},
                                 conflict_callback => { optional => 1 } } );
    my $source = $args{'from'};

    return unless $self->ressource;

    $self->ressource->import_changesets( from => $source->ressource,
                                             resolver => sub { die "nono not yet" } );

    my $records = Prophet::Collection->new(handle => $self->ressource->prophet_handle, type => '_prophet_resolution');
    return $records;
}



1;
