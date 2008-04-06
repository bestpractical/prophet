use warnings;
use strict;

package Prophet::Replica;
use base qw/Class::Accessor/;
use Params::Validate qw(:all);
use UNIVERSAL::require;

__PACKAGE__->mk_accessors(qw(state_handle ressource is_resdb));

use constant state_db_uuid => 'state';


=head1 NAME

Prophet::Replica

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
        $class = 'Prophet::Replica::RT';
    } elsif ($args->{url} =~ /^hm:/ ) {
        $class = 'Prophet::Replica::Hiveminder';
    } elsif ($args->{url} =~ s/^prophet://) {
        $class = 'Prophet::Replica::HTTP';
    } else {
        $class = 'Prophet::Replica::SVN';
    }
    $class->require or die $@;
    bless $self, $class;
}

sub import_changesets {
    my $self = shift;
    my %args = validate(
        @_,
        {   from               => { isa      => 'Prophet::Replica' },
            resdb              => { optional => 1 },
            resolver           => { optional => 1 },
            resolver_class     => { optional => 1 },
            conflict_callback  => { optional => 1 },
            reporting_callback => { optional => 1 }
        }
    );

    my $source = $args{'from'};

    my $changesets_to_integrate = $source->new_changesets_for($self);

    for my $changeset (@$changesets_to_integrate) {
        $self->integrate_changeset(
            changeset          => $changeset,
            conflict_callback  => $args{conflict_callback},
            reporting_callback => $args{'reporting_callback'},
            resolver           => $args{resolver},
            resolver_class     => $args{'resolver_class'},
            resdb              => $args{'resdb'},
        );

    }
}

sub import_resolutions_from_remote_replica {
    my $self = shift;
    my %args = validate(
        @_,
        {   from              => { isa      => 'Prophet::Replica' },
            resolver          => { optional => 1 },
            resolver_class    => { optional => 1 },
            conflict_callback => { optional => 1 }
        }
    );
    my $source = $args{'from'};

    return unless $self->ressource;
    return unless $source->ressource;

    $self->ressource->import_changesets(
        from     => $source->ressource,
        resolver => sub { die "nono not yet" }

    );
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
    my $self      = shift;
    my $changeset = shift;

    $self->record_changeset($changeset);

    my $state_handle = $self->state_handle;

    my $inside_edit = $state_handle->current_edit ? 1 : 0;
    $state_handle->begin_edit() unless ($inside_edit);
    $state_handle->record_changeset_integration($changeset);
    $state_handle->commit_edit() unless ($inside_edit);

    return;
}


=head2 last_changeset_from_source $SOURCE_UUID

Returns the last changeset id seen from the source identified by $SOURCE_UUID

=cut

sub last_changeset_from_source {
    my $self = shift;
    my ($source) = validate_pos( @_, { type => SCALAR } );

    return $self->state_handle->_retrieve_metadata_for( $Prophet::Handle::MERGETICKET_METATYPE, $source, 'last-changeset' ) || 0;

    # XXXX the code below is attempting to get the content over ra so we
    # can deal with remote svn repo. however this also assuming the
    # remote is having the same prophet_handle->db_rot 
    # the code to handle remote svn should be
    # actually abstracted along when we design the sync prototype

    my ( $stream, $pool );

    my $filename = join( "/", $self->prophet_handle->db_uuid, $Prophet::Handle::MERGETICKET_METATYPE, $source );
    my ( $rev_fetched, $props )
        = eval { $self->ra->get_file( $filename, $self->most_recent_changeset, $stream, $pool ); };

    # XXX TODO this is hacky as hell and violates abstraction barriers in the name of doing things over the RA
    # because we want to be able to sync to a remote replica someday.

    return ( $props->{'last-changeset'} || 0 );

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
            !( $_->node_type eq $Prophet::Handle::MERGETICKET_METATYPE && $_->node_uuid eq $self->uuid )
            } $changeset->changes
    ];
}


=head2 news_changesets_for Prophet::Replica

Returns the local changesets that have not yet been seen by the replica we're passing in.

=cut

sub db_uuid {
    my $self = shift;
    return undef unless ($self->can('prophet_handle'));
    return $self->prophet_handle->db_uuid;

}

sub new_changesets_for {
    my $self = shift;
    my (  $other ) = validate_pos(@_, { isa => 'Prophet::Replica'});
    if ($self->db_uuid && $other->db_uuid && $self->db_uuid ne $other->db_uuid) {
        warn "HEY. You should not be merging between two replicas with different database uuids";

    }

    return [ 
        grep { $self->should_send_changeset( changeset => $_, to => $other ) }
                    @{ $self->fetch_changesets( after => $other->last_changeset_from_source( $self->uuid ) ) } 
        ];
}

=head2 should_send_changeset { to => Prophet::Replica, changeset => Prophet::ChangeSet }

Returns true if the replica C<to> hasn't yet seen the changeset C<changeset>


=cut

sub should_send_changeset {
    my $self = shift;
    my %args = validate(@_, { to => { isa => 'Prophet::Replica'}, changeset =>{ isa=> 'Prophet::ChangeSet' }});
    
     return undef if ( $args{'changeset'}->is_nullification || $args{'changeset'}->is_resolution );
     return undef if $args{'to'}->has_seen_changeset($args{'changeset'});
     
    return 1;     
}

=head2 fetch_changesets { after => SEQUENCE_NO } 

Fetch all changesets from the source. 
        
Returns a reference to an array of L<Prophet::ChangeSet/> objects.
        

=cut    
        
sub fetch_changesets {
    my $self = shift;
    my %args = validate( @_, { after => 1 } );
    my @results;

    my $first_rev = ( $args{'after'} + 1 ) || 1;

    # XXX TODO we should  be using a svn get_log call here rather than simple iteration
    # clkao explains that this won't deal cleanly with cases where there are revision "holes"
    for my $rev ( $first_rev .. $self->most_recent_changeset) {
        push @results, $self->fetch_changeset($rev);
    }


    return \@results;
}

use Path::Class;
use Digest::SHA1 qw(sha1 sha1_hex);
use XML::Simple;

=head2 export_to


filesystem replica type
 
 $URL
    /<db-uuid>/
        /replica-uuid
        /latest
        /cas/<substr(sha1,0,1)>/substr(sha1,1,1)/<sha1>
        /records (optional?)
            /<record type> (for resolution is actually _prophet-resolution-<cas-key>)
                /<record uuid> which is a file containing a list of 0 or more rows
                    last-changed-sequence-no : cas key
                                    
        /changesets.idx
    
            index which has records:
                each record is : local-replica-seq-no : original-uuid : original-seq-no : cas key
            ...
    
        /resolutions/
            /replica-uuid
            /latest
            /cas/<substr(sha1,0,1)>/substr(sha1,1,1)/<sha1>
            /content (optional?)
                /_prophet-resolution-<cas-key>   (cas-key == a hash the conflicting change)
                    /<record uuid>  (record uuid == the originating replica)
                        last-changed-sequence-no : <cas key to the content of the resolution>
                                        
            /changesets.idx
                index which has records:
                    each record is : local-replica-seq-no : original-uuid : original-seq-no : cas key
                ...

=cut


sub export_to {
    my $self = shift;
    my $path = shift;

    my $replica_root = dir( $path, $self->db_uuid );
    _mkdir($path);
    _mkdir($replica_root);

    open( my $uuidfile, ">", file( $replica_root, 'replica-uuid' ) ) || die $!;
    print $uuidfile $self->uuid || die $!;
    close $uuidfile || die $!;
    open( my $latest, ">", file( $replica_root, 'latest' ) ) || die $!;
    print $latest $self->most_recent_changeset;
    close $latest || die $!;

    make_tiered_dirs( dir( $replica_root => 'cas' ) );
    _mkdir( dir( $replica_root => 'records' ) );
    _mkdir( dir( $replica_root => 'records' => 'some_record_type' ) );

    foreach my $type ( @{ $self->prophet_handle->enumerate_types } ) {

        make_tiered_dirs( dir( $replica_root => 'records' => $type ) );

        my $collection = Prophet::Collection->new( handle => $self->prophet_handle, type => $type );
        $collection->matching( sub {1} );
        foreach my $record (@$collection) {
            my $record_as_hash = $record->get_props;
            my $content = XMLout( $record_as_hash, NoAttr => 1, RootName => 'record' );
            my $fingerprint = sha1_hex($content);
            my $content_filename
                = file( $replica_root, 'cas', substr( $fingerprint, 0, 1 ), substr( $fingerprint, 1, 1 ),
                $fingerprint );
            open( my $output, ">", $content_filename ) || die "Could not open $content_filename";
            print $output $content || die $!;
            close $output;

            my $idx_filename = file(
                $replica_root, 'records',$type,
                substr( $record->uuid, 0, 1 ),
                substr( $record->uuid, 1, 1 ),
                $record->uuid
            );

            open(my $record_index, ">>", $idx_filename ) || die $!;

            # XXX TODO: skip if the index already has this version of the record;
            my $record_last_changed_changeset = 1;

            # XXX TODO FETCH THAT
            print $record_index pack( 'Na16a20', $record_last_changed_changeset, $record->uuid, sha1_hex($content) )
                || die $!;
            close $record_index;

        }

    }

    open( my $cs_file, ">" . file( $replica_root, 'changesets.idx' ) ) || die $!;

    foreach my $changeset ( @{ $self->fetch_changesets( after => 0 ) } ) {
        my $hash_changeset = $changeset->as_hash;
        delete $hash_changeset->{'sequence_no'};
        delete $hash_changeset->{'source_uuid'};

        my $content = XMLout( $hash_changeset, NoAttr => 1, RootName => 'changeset' );
        my $fingerprint = sha1_hex($content);
        my $content_filename
            = file( $replica_root, 'cas', substr( $fingerprint, 0, 1 ), substr( $fingerprint, 1, 1 ), $fingerprint );
        open( my $output, ">", $content_filename ) || die "Could not open $content_filename";
        print $output $content || die $!;
        close $output;

        # XXX TODO we should only actually be encoding the sha1 of content once
        # and then converting. this is wasteful
        print $cs_file pack( 'Na16Na20',
            $changeset->sequence_no,
            $changeset->original_source_uuid,
            $changeset->original_sequence_no,
            sha1($content) )
            || die $!;

    }

    close($cs_file);
}


sub _mkdir {
    my $path = shift;
    unless (-d $path) {
        mkdir ($path) || die $@;
    }
    unless (-w $path) {
        die "$path not writable";
    }


}

    sub make_tiered_dirs {
        my $base = shift;
        _mkdir(dir($base));
    for my $a (0..9, 'a'..'f') {
        _mkdir(dir($base => $a));
        for my $b (0..9, 'a'..'f') {
        _mkdir(dir($base => $a => $b));
        }
    }


}

    
sub serialize_changeset {
    my $self = shift;
    my $changeset_id = shift;
    $self->fetch_changeset($changeset_id);

}


sub serialize_node {

}


1;
