use warnings;
use strict;

package Prophet::Sync::Source;
use base qw/Class::Accessor/;
use Params::Validate qw(:all);
use UNIVERSAL::require;

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
    $self->rebless_to_replica_type(@_);
    $self->setup();
    return $self;
}

=head2 rebless_to_replica_type

Reblesses this sync source into the right sort of sync source for whatever kind of replica $self->url points to

TODO: currently knows that we only have SVN replicas


=cut

sub rebless_to_replica_type {
    my $self = shift;
    my $args = shift;

    my $class;

    # XXX TODO HACK NEED A PROPER WAY TO DETERMINE SYNC SOURCE
    if ( $args->{url} =~ /^rt:/ ) {
        $class = 'Prophet::Sync::Source::RT';
    } else {
        $class = 'Prophet::Sync::Source::SVN';
    }
    $class->require or die $@;
    bless $self, $class;
}

sub import_changesets {
    my $self = shift;
    my %args = validate(
        @_,
        {   from               => { isa      => 'Prophet::Sync::Source' },
            use_resdb          => { optional => 1 },
            resolver           => { optional => 1 },
            resolver_class     => { optional => 1 },
            conflict_callback  => { optional => 1 },
            reporting_callback => { optional => 1 }
        }
    );

    my $source = $args{'from'};

    my $resdb = $args{use_resdb} ? $self->fetch_resolutions( from => $source ) : undef;

    my $changesets_to_integrate = $source->new_changesets_for($self);

    for my $changeset (@$changesets_to_integrate) {
        $self->integrate_changeset(
            changeset          => $changeset,
            conflict_callback  => $args{conflict_callback},
            reporting_callback => $args{'reporting_callback'},
            resolver           => $args{resolver},
            resolver_class     => $args{'resolver_class'},
            resdb              => $resdb
        );

    }
}

=head2 integrate_changeset L<Prophet::ChangeSet>

If there are conflicts, generate a nullification change, figure out a conflict resolution and apply the nullification, original change and resolution all at once (as three separate changes).

If there are no conflicts, just apply the change.

=cut

sub integrate_changeset {
    my $self = shift;
    my %args = validate(
        @_,
        {   changeset          => { isa      => 'Prophet::ChangeSet' },
            resolver           => { optional => 1 },
            resolver_class     => { optional => 1 },
            resdb              => { optional => 1 },
            conflict_callback  => { optional => 1 },
            reporting_callback => { optional => 1 }
        }
    );

    my $changeset = $args{'changeset'};

    # when we start to integrate a changeset, we need to do a bit of housekeeping
    # We never want to merge in:
    # merge tickets that describe merges from the local node

    # When we integrate changes, sometimes we will get handed changes we already know about.
    #   - changes from local
    #   - changes from some other party we've merged from
    #   - merge tickets for the same
    # we'll want to skip or remove those changesets

    return if $changeset->original_source_uuid eq $self->uuid;

    $self->remove_redundant_data($changeset);    #Things we have already seen

    return if ( $changeset->is_empty or $changeset->is_nullification );

    if ( my $conflict = $self->conflicts_from_changeset($changeset) ) {
        $args{conflict_callback}->($conflict) if $args{'conflict_callback'};
        $conflict->resolvers( [ sub { $args{resolver}->(@_) } ] ) if $args{resolver};
        if ( $args{resolver_class} ) {
            $args{resolver_class}->require || die $@;
            $conflict->resolvers(
                [   sub {
                        $args{resolver_class}->new->run(@_);
                        }
                ]
                )

        }
        my $resolutions = $conflict->generate_resolution( $args{resdb} );

        #figure out our conflict resolution

     # IMPORTANT: these should be an atomic unit. dying here would be poor.  BUT WE WANT THEM AS THREEDIFFERENT SVN REVS
     # integrate the nullification change
        $self->record_changeset( $conflict->nullification_changeset );

        # integrate the original change
        $self->record_integration_changeset($changeset);

        # integrate the conflict resolution change
        $self->record_resolutions( $conflict->resolution_changeset );

        #            $self->ressource ? $self->ressource->prophet_handle : $self->prophet_handle );
        $args{'reporting_callback'}->( changeset => $changeset, conflict => $conflict )
            if ( $args{'reporting_callback'} );

    } else {
        $self->record_integration_changeset($changeset);
        $args{'reporting_callback'}->( changeset => $changeset ) if ( $args{'reporting_callback'} );

    }
}

=head2 record_changeset
=cut

sub record_changeset {
    die ref( $_[0] ) . ' must implement record_changeset';
}

=head2 record_integration_changeset

=cut

sub record_integration_changeset {
    die ref( $_[0] ) . ' must implement record_changeset';
}

=head2 accepts_changesets

Returns true if this source is one we know how to write to (and have permission to write to)

Returns false otherwise

=cut

sub accepts_changesets {
    my $self = shift;

    return 1 if $self->prophet_handle;
    return undef;
}

=head2 has_seen_changeset Prophet::ChangeSet

Returns true if we've previously integrated this changeset, even if we originally recieved it from a different peer

=cut

sub has_seen_changeset {
    my $self = shift;
    my ($changeset) = validate_pos( @_, { isa => "Prophet::ChangeSet" } );

    # If the changeset originated locally, we never want it
    return 1 if $changeset->original_source_uuid eq $self->uuid;

    # Otherwise, if the we have a merge ticket from the source, we don't want the changeset
    my $last = $self->last_changeset_from_source( $changeset->original_source_uuid );

    # if the source's sequence # is >= the changeset's sequence #, we can safely skip it
    return 1 if ( $last >= $changeset->original_sequence_no );
    return undef;
}

=head2 changeset_will_conflict Prophet::ChangeSet

Returns true if any change that's part of this changeset won't apply cleanly to the head of the current replica

=cut

sub changeset_will_conflict {
    my $self = shift;
    my ($changeset) = validate_pos( @_, { isa => "Prophet::ChangeSet" } );

    return 1 if ( $self->conflicts_from_changeset($changeset) );

    return undef;

}

=head2 conflicts_from_changeset Prophet::ChangeSet

Returns a L<Prophet::Conflict/> object if the supplied L<Prophet::ChangeSet/>
will generate conflicts if applied to the current replica.

Returns undef if the current changeset wouldn't generate a conflict.

=cut

sub conflicts_from_changeset {
    my $self = shift;
    my ($changeset) = validate_pos( @_, { isa => "Prophet::ChangeSet" } );

    my $conflict = Prophet::Conflict->new( { changeset => $changeset, prophet_handle => $self->prophet_handle } );

    $conflict->analyze_changeset();

    return undef unless @{ $conflict->conflicting_changes };

    return $conflict;

}

sub remove_redundant_data {
    my ( $self, $changeset ) = @_;

    # XXX: encapsulation
    $changeset->{changes} = [
        grep { $self->is_resdb || $_->node_type ne '_prophet_resolution' } grep {
            !( $_->node_type eq $Prophet::Handle::MERGETICKET_METATYPE && $_->node_uuid eq $self->prophet_handle->uuid )
            } $changeset->changes
    ];
}

sub fetch_resolutions {
    my $self = shift;
    my %args = validate(
        @_,
        {   from              => { isa      => 'Prophet::Sync::Source' },
            resolver          => { optional => 1 },
            resolver_class    => { optional => 1 },
            conflict_callback => { optional => 1 }
        }
    );
    my $source = $args{'from'};

    return unless $self->ressource;

    $self->ressource->import_changesets(
        from     => $source->ressource,
        resolver => sub { die "nono not yet" }

    );

    my $records = Prophet::Collection->new( handle => $self->ressource->prophet_handle, type => '_prophet_resolution' );
    return $records;
}

=head2 news_changesets_for

Returns the local changesets that are new to the replica $other.

=cut

sub new_changesets_for {
    my ( $self, $other ) = @_;

    my $since = $other->last_changeset_from_source( $self->uuid );

    return [ grep { !( $_->is_nullification || $_->is_resolution ) && !$other->has_seen_changeset($_) }
            @{ $self->fetch_changesets( after => $since ) } ];

}

1;
