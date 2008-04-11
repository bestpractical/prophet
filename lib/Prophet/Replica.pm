use warnings;
use strict;

package Prophet::Replica;
use base qw/Class::Accessor/;
use Params::Validate qw(:all);
use UNIVERSAL::require;


__PACKAGE__->mk_accessors(qw(state_handle ressource is_resdb url));

use constant state_db_uuid => 'state';
use Module::Pluggable search_path => 'Prophet::Replica', sub_name => 'core_replica_types', require => 1, except => qr/Prophet::Replica::(.*)::/;

our $REPLICA_TYPE_MAP = {};
 __PACKAGE__->register_replica_scheme(scheme => $_->scheme, class => $_) for ( __PACKAGE__->core_replica_types);

=head1 NAME

Prophet::Replica

=head1 DESCRIPTION
                        
A base class for all Prophet replicas

=cut

=head1 METHODS

=head2 new

Instantiates a new replica

=cut

sub _unimplemented { my $self = shift; die ref($self). " does not implement ". shift; }

sub new {
    my $self = shift->SUPER::new(@_);
    $self->_rebless_to_replica_type(@_);
    $self->setup();
    return $self;
}

=head2 register_replica_scheme { class=> Some::Perl::Class, scheme => 'scheme:' }

B<Class Method>. Register a URI scheme C<scheme> to point to a replica object of type C<class>.

=cut

sub register_replica_scheme {
    my $class = shift;
    my %args = validate(@_, { class => 1, scheme => 1});

    $Prophet::Replica::REPLICA_TYPE_MAP->{$args{'scheme'}} = $args{'class'};



}


=head2 _rebless_to_replica_type

Reblesses this replica into the right sort of replica for whatever kind of replica $self->url points to


=cut

sub _rebless_to_replica_type {
    my $self = shift;


    my ($scheme, $real_url) = split(/:/,$self->url,2);
    $self->url($real_url);
    if ( my $class = $Prophet::Replica::REPLICA_TYPE_MAP->{$scheme}) {
    $class->require or die $@;
    return bless $self, $class;
    } else {
        die "$scheme isn't a replica type I know how to handle";
    }
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

    $source->traverse_new_changesets(
        for      => $self,
        callback => sub {
            $self->integrate_changeset(
                changeset          => $_[0],
                conflict_callback  => $args{conflict_callback},
                reporting_callback => $args{'reporting_callback'},
                resolver           => $args{resolver},
                resolver_class     => $args{'resolver_class'},
                resdb              => $args{'resdb'},
            );
        }
    );
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

=head2 record_resolutions Prophet::Changeset

Record a Prophet::ChangeSet containing a set of resolutions to a resolution database

=cut

sub record_resolutions {
    my $self = shift;
    my ($changeset) = validate_pos(@_, { isa => 'Prophet::ChangeSet'});
    if ($self->accepts_changesets) {
        $self->prophet_handle->record_resolutions( $changeset,  $self->ressource ? $self->ressource->prophet_handle : $self->prophet_handle );
    } else {
        $self->_unimplemented("record_resolutions (since there is no writable handle)");
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

=head2 record_integration_changeset

=cut

sub record_integration_changeset {
    my $self      = shift;
    my $changeset = shift;

    $self->prophet_handle->begin_edit;
    $self->record_changeset($changeset);

    my $state_handle = $self->state_handle;
    my $inside_edit = $state_handle->current_edit ? 1 : 0;
    $state_handle->begin_edit() unless ($inside_edit);
    $state_handle->record_changeset_integration($changeset);
    $state_handle->commit_edit() unless ($inside_edit);
    
    $self->prophet_handle->commit_edit;

    return;
}

=head2 last_changeset_from_source $SOURCE_UUID

Returns the last changeset id seen from the source identified by $SOURCE_UUID

=cut

sub last_changeset_from_source {
    my $self = shift;
    my ($source) = validate_pos( @_, { type => SCALAR } );

    return $self->state_handle->_retrieve_metadata_for( $Prophet::Handle::MERGETICKET_METATYPE, $source,
        'last-changeset' )
        || 0;

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


=head2 record_changeset Prophet::ChangeSet 

Record a Prophet::ChangeSet to this replica (passes through to the current prophet handle)

=cut

sub record_changeset {
    my $self = shift;
    my ($changeset) = validate_pos(@_, { isa => 'Prophet::ChangeSet'});
    if ($self->accepts_changesets) {
    $self->prophet_handle->record_changeset($changeset);
    } else {
        $self->_unimplemented ('record_changeset');
    }

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
        grep { $self->is_resdb || $_->node_type ne '_prophet_resolution' }
            grep { !( $_->node_type eq $Prophet::Handle::MERGETICKET_METATYPE && $_->node_uuid eq $self->uuid ) }
            $changeset->changes
    ];
}

=head2 traverse_new_changesets ( for => $replica, callback => sub { my $changeset = shift; ... } )

Traverse the new changesets for C<$replica> and call C<callback> for each new changesets.

XXX: this also provide hinting callbacks for the caller to know in
advance how many changesets are there for traversal.

=cut

sub traverse_new_changesets {
    my $self = shift;
    my %args = validate(
        @_,
        {   for      => { isa => 'Prophet::Replica' },
            callback => 1,
        }
    );

    if ( $self->db_uuid && $args{for}->db_uuid && $self->db_uuid ne $args{for}->db_uuid ) {

        #warn "HEY. You should not be merging between two replicas with different database uuids";
        # XXX TODO
    }

    $self->traverse_changesets(
        after    => $args{for}->last_changeset_from_source( $self->uuid ),
        callback => sub {
            $args{callback}->( $_[0] )
                if $self->should_send_changeset( changeset => $_[0], to => $args{for} );
        }
    );
}

=head2 news_changesets_for Prophet::Replica

DEPRECATED: use traverse_new_changesets instead

Returns the local changesets that have not yet been seen by the replica we're passing in.

=cut

sub db_uuid {
    my $self = shift;
    return undef unless ( $self->can('prophet_handle') );
    return $self->prophet_handle->db_uuid;

}

sub new_changesets_for {
    my $self = shift;
    my ($other) = validate_pos( @_, { isa => 'Prophet::Replica' } );

    my @result;
    $self->traverse_new_changesets( for => $other, callback => sub { push @result, $_[0] } );

    return \@result;
}

=head2 should_send_changeset { to => Prophet::Replica, changeset => Prophet::ChangeSet }

Returns true if the replica C<to> hasn't yet seen the changeset C<changeset>


=cut

sub should_send_changeset {
    my $self = shift;
    my %args = validate( @_, { to => { isa => 'Prophet::Replica' }, changeset => { isa => 'Prophet::ChangeSet' } } );

    return undef if ( $args{'changeset'}->is_nullification || $args{'changeset'}->is_resolution );
    return undef if $args{'to'}->has_seen_changeset( $args{'changeset'} );

    return 1;
}

=head2 fetch_changesets { after => SEQUENCE_NO } 

Fetch all changesets from the source. 
        
Returns a reference to an array of L<Prophet::ChangeSet/> objects.

See also L<traverse_new_changesets> for replica implementations to provide streamly interface
        

=cut    

sub fetch_changesets {
    my $self = shift;
    my %args = validate( @_, { after => 1 } );
    my @results;

    $self->traverse_changesets( %args, callback => sub { push @results, $_[0] } );

    return \@results;
}

sub traverse_changesets {
    my $self = shift;
    my %args = validate(
        @_,
        {   after    => 1,
            callback => 1,
        }
    );

    my $first_rev = ( $args{'after'} + 1 ) || 1;
    my $last_rev = $self->most_recent_changeset();


    die "you must implement most_recent_changeset in " . ref($self) . ", or override traverse_changesets"
        unless defined $last_rev;

    for my $rev ( $first_rev .. $self->most_recent_changeset ) {
        $args{callback}->( $self->fetch_changeset($rev) );
    }
}

use Path::Class;
use Digest::SHA1 qw(sha1 sha1_hex);
use YAML::Syck;

=head2 export_to { path => $PATH } 

This routine will export a copy of this prophet database replica to a flat file on disk suitable for 
publishing via HTTP or over a local filesystem for other Prophet replicas to clone or incorporate changes from.


=head3 text-dump replica format

=head4 overview
 
 $URL
    /<db-uuid>/
        /replica-uuid
        /latest-sequence-no
        /replica-version
        /cas/records/<substr(sha1,0,1)>/substr(sha1,1,1)/<sha1>
        /cas/changesets/<substr(sha1,0,1)>/substr(sha1,1,1)/<sha1>
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
            /latest-sequence-no
            /cas/<substr(sha1,0,1)>/substr(sha1,1,1)/<sha1>
            /content (optional?)
                /_prophet-resolution-<cas-key>   (cas-key == a hash the conflicting change)
                    /<record uuid>  (record uuid == the originating replica)
                        last-changed-sequence-no : <cas key to the content of the resolution>
                                        
            /changesets.idx
                index which has records:
                    each record is : local-replica-seq-no : original-uuid : original-seq-no : cas key
                ...


Inside the top level directory for the mirror, you'll find a directory named as B<a hex-encoded UUID>.
This directory is the root of the published replica. The uuid uniquely identifes the database being replicated.
All replicas of this database will share the same UUID.

Inside the B<<db-uuid>> directory, are a set of files and directories that make up the actual content of the database replica:

=over 2

=item C<replica-uuid>

Contains the replica's hex-encoded UUID.

=item C<replica-version>

Contains a single integer that defines the replica format.

The current replica version is 1.

=item C<latest-sequence-no>

Contains a single integer, the replica's most recent sequence number.

=item C<cas/records>

=item C<cas/changesets>

The C<cas> directory holds changesets and records, each keyed by a
hex-encoded hash of the item's content. Inside the C<cas> directory, you'll find
a two-level deep directory tree of single-character hex digits. 
You'll find  the changeset with the sha1 digest  C<f4b7489b21f8d107ad8df78750a410c028abbf6c>
inside C<cas/changesets/f/4/f4b7489b21f8d107ad8df78750a410c028abbf6c>.

You'll find the record with the sha1 digest C<dd6fb674de879a1a4762d690141cdfee138daf65> inside
C<cas/records/d/d/dd6fb674de879a1a4762d690141cdfee138daf65>.


TODO: define the format for changesets and records


=item C<records>

Files inside the C<records> directory are index files which list off all published versions of a record and the key necessary to retrieve the record from the I<content-addressed store>.

Inside the C<records> directory, you'll find directories named for each
C<type> in your database. Inside each C<type> directory, you'll find a two-level directory tree of single hexadecimal digits. You'll find the record with the type <Foo> and the UUID C<29A3CA16-03C5-11DD-9AE0-E25CFCEE7EC4> stored in 

 records/Foo/2/9/29A3CA16-03C5-11DD-9AE0-E25CFCEE7EC4


The format of record files is:

    <unsigned-long-int: last-changed-sequence-no><40 chars of hex: cas key>

The file is sorted in asecnding order by revision id.


=item C<changesets.idx>

The C<changesets.idx> file lists each changeset in this replica and
provides an index into the B<content-addressed storage> to fetch
the content of the changeset.

The format of record files is:

    <unsigned-long-int: sequence-no><16 bytes: changeset original source uuid><unsigned-long-int: changeset original source sequence no><16 bytes: cas key - sha1 sum of the changeset's content>

The file is sorted in ascending order by revision id.


=item C<resolutions>

=over 2

=item TODO DOC RESOLUTIONS


=back

=back

=cut

sub export_to {
    my $self = shift;
    my %args = validate( @_, { path => 1, } );
    Prophet::ReplicaExporter->require();

    my $exporter = Prophet::ReplicaExporter->new({target_path => $args{'path'}, replica => $self});
    $exporter->export();
}




=head1 methods to be implemented by a replica backend



=cut


=head2 uuid 

Returns this replica's uuid

=cut

sub uuid {}

=head2 most_recent_changeset

Returns the sequence # of the most recently committed changeset

=cut

sub most_recent_changeset {return undef }

=head2 fetch_changeset SEQUENCE_NO

Returns a Prophet::ChangeSet object for changeset # C<SEQUENCE_NO>

=cut

sub fetch_changeset {} 


1;
