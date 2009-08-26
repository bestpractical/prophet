package Prophet::Replica;
use Any::Moose;
use Params::Validate qw(:all);
use File::Spec ();
use File::Path qw/mkpath/;

use constant state_db_uuid => 'state';

use Prophet::App;

has metadata_store => (
    is => 'rw',
    isa => 'Prophet::MetadataStore',
    documentation => 'Where metadata about other replicas is stored.',
);


has resolution_db_handle => (
    is  => 'rw',
    isa => 'Prophet::Replica',
    documentation => 'Where conflict resolutions are stored.',
);

has is_resdb => (
    is  => 'rw',
    isa => 'Bool',
    documentation => 'Whether this replica is a resolution db or not.'
);

has db_uuid => (
    is     => 'rw',
    isa    => 'Str',
    documentation => 'The uuid of this replica.',
);
sub set_db_uuid { shift->db_uuid(@_) }

has url => (
    is  => 'rw',
    isa => 'Str',
    documentation => 'Where this replica comes from.',
);

has app_handle => (
    is        => 'ro',
    isa       => 'Prophet::App',
    weak_ref  => 1,
    predicate => 'has_app_handle',
);

has after_initialize => ( 
    is => 'rw',
    isa => 'CodeRef',
    default => sub { sub {1} } # default returns a coderef
    );


has uuid_generator => (
    is      => 'rw',
    isa     => 'Prophet::UUIDGenerator',
    lazy    => 1,
    default => sub {
        my $self = shift;
        my $ug = Prophet::UUIDGenerator->new( uuid_scheme => 2 );
        return $ug;

    }
);



our $MERGETICKET_METATYPE = '_merge_tickets';

=head1 NAME

Prophet::Replica

=head1 DESCRIPTION

A base class for all Prophet replicas.

=head1 METHODS

=head3 get_handle

Determines what replica class to use and instantiates it. Returns the
new replica object.

=cut

sub get_handle {
    my $class = shift;
    my %args = @_ == 1 ? %{ $_[0] } : @_;

    my ( $new_class, $scheme, $url ) = $class->_url_to_replica_class(%args);

    if ( !$new_class ) {
        $class->log_fatal(
            "I don't know how to handle the replica URL you provided - '@{[ $args{url}]}'."
            ."\nIs your syntax correct?"
        );
    }

    Prophet::App->require($new_class);
    my $handle = $new_class->new(%args);

    if ($handle->replica_exists && $handle->db_uuid) {
        $handle->uuid_generator->set_uuid_scheme($handle->db_uuid);
    }

    return $handle;
}



sub initialize {
    my $self = shift;
    my %args = validate(
        @_,
        {   db_uuid            => 0,
            replica_uuid       => 0,
            resdb_uuid         => 0,
            resdb_replica_uuid => 0,
        }
    );

    if ( !$self->fs_root_parent ) {

        if ( $self->can_write_changesets ) {
            die "We can only create local prophet replicas. It looks like you're trying to create " . $self->url;
        } else {
            die "Prophet couldn't find a replica at \""
                . $self->url
                . "\"\n\n"
                . "Please check the URL and try again.\n";

        }
    }

    return undef if $self->replica_exists;

    $self->uuid_generator->set_uuid_scheme($args{'db_uuid'}) if ($args{db_uuid});

    for ( $self->_on_initialize_create_paths ) {
        mkpath( [ File::Spec->catdir( $self->fs_root => $_ ) ] );
    }

    $self->initialize_backend(%args);
    $self->after_initialize->($self);
}



=head2 store_local_metadata KEY => VALUE

Takes a key and a value.

Store some bit of metadata in a durable local datastore.  Metadata isn't propagated
when replicas are synced.

Returns true or false.

=cut

=head2 fetch_local_metadata KEY

Takes a scalar key.

Fetches a bit of metadata from the local metadata store.

Returns the value of the key found in the local metadata store. 

Returns undef if there's no value for the key in the local metadata store.

=cut

sub replica_exists {
    return 1; # XXX TODO HACK
}

sub can_initialize {
    return undef;
}

=head3 _url_to_replica_class

Returns the replica class for the given url based on its scheme.

=cut

sub _url_to_replica_class {
    my $self = shift;
    my %args = (@_);
    my $url = $args{'url'};
    my ( $scheme, $real_url ) = $url =~ /^([^:]*?):(.*)$/;

    return undef unless $scheme;

    for my $class ( 
        ref( $args{app_handle} ) . "::Replica::" . $scheme,
        "Prophet::Replica::".$scheme ) {
        Prophet::App->try_to_require($class) || next;
        return ( $class, $scheme, $real_url );
    }
    return undef;
}

=head3 import_changesets { from => L<Prophet::Replica> ... }

Given a L<Prophet::Replica> to import changes from, traverse all the
changesets we haven't seen before and integrate them into this replica.

This routine calls L<traverse_changesets> on the 'from' replica,
passing in the most recent changeset the current replica has seen
and a callback routine which calls L<integrate_changeset> on the
local replica.

That callback itself takes a callback, L<after_integrate_changeset>
, which a replica implementation can use to perform some action
after a changeset is integrated into a peer.  L<after_integrate_changeset>
takes a paramhash, currently with only a single key, 'changeset'.

=cut

sub import_changesets {
    my $self = shift;
    my %args = validate(
        @_,
        {   from                      => { isa      => 'Prophet::Replica' },
            resdb                     => { optional => 1 },
            resolver                  => { optional => 1 },
            resolver_class            => { optional => 1 },
            conflict_callback         => { type => CODEREF, optional => 1 },
            reporting_callback        => { type => CODEREF, optional => 1 },
            force                     => { optional => 1 },
        }
    );

    my $source = $args{'from'};

    $self->_check_db_uuids_on_merge(for => $source, force => $args{'force'});

    warn "The source (@{[$source->url]}) does not exist"
        unless ($source->replica_exists);

    $self->log_debug("Integrating changesets from ".$source->uuid.
        " after ". $self->last_changeset_from_source( $self->uuid ));

    $source->traverse_changesets(
        after                          =>
            $self->last_changeset_from_source( $source->uuid ),
        before_load_changeset_callback => sub {
                my %args = (@_);
                my ($seq, $orig_uuid, $orig_seq, $key)
                    = @{$args{changeset_metadata}};
                # skip changesets we've seen before
                if ( $self->has_seen_changeset( source_uuid => $orig_uuid,
                        sequence_no => $orig_seq) ){
                    # If we've seen the changeset, yet we still got here, it
                    # means we saw it by original

                    # replica/sequence pair, but not # the direct upstream's
                    # uuid/sequence pair.
                    # recording that can help performance a whole bunch for
                    # next sync
                    if ($source->uuid && $seq && $seq
                        > $self->last_changeset_from_source($source->uuid)) {
                          $self->record_last_changeset_from_replica(
                              $source->uuid => $seq);
                    }
                    return undef;
                } else {
                    return 1;
                }

            },
        callback                       => sub {
            my %callback_args = (@_);
            $self->integrate_changeset(
                changeset          => $callback_args{changeset},
                conflict_callback  => $args{'conflict_callback'},
                reporting_callback => $args{'reporting_callback'},
                resolver           => $args{'resolver'},
                resolver_class     => $args{'resolver_class'},
                resdb              => $args{'resdb'},
            );

            if ( ref( $callback_args{'after_integrate_changeset'} ) ) {
                $callback_args{'after_integrate_changeset'}->(
                    changeset => $callback_args{'changeset'} );
            }

        }
    );
}

=head3 import_resolutions_from_remote_replica { from => L<Prophet::Replica> ... }

Takes a L<Prophet::Replica> object (and possibly some optional arguments)
and imports its resolution changesets into this replica's resolution
database.

Returns immediately if either the source replica or the target replica lack
a resolution database.

=cut

sub import_resolutions_from_remote_replica {
    my $self = shift;
    my %args = validate(
        @_,
        {   from              => { isa      => 'Prophet::Replica' },
            resolver          => { optional => 1 },
            resolver_class    => { optional => 1 },
            conflict_callback => { optional => 1 },
            force             => { optional => 1 },
        }
    );
    my $source = $args{'from'};

    return unless $self->resolution_db_handle;
    return unless $source->resolution_db_handle;

    $self->resolution_db_handle->import_changesets(
        from     => $source->resolution_db_handle,
        resolver => sub { die "not implemented yet" },
        force    => $args{force},
    );
}

=head3 integrate_changeset L<Prophet::ChangeSet>

Given a L<Prophet::ChangeSet>, integrate each and every change within that
changeset into the handle's replica.

If there are conflicts, generate a nullification change, figure out a conflict
resolution and apply the nullification, original change and resolution all at
once (as three separate changes).

If there are no conflicts, just apply the change.

This routine also records that we've seen this changeset (and hence everything
before it) from both the peer who sent it to us AND the replica which originally
created it.

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


    $self->log_debug("Considering changeset ".$changeset->original_sequence_no .
        " from " . $self->display_name_for_replica($changeset->original_source_uuid));

    # when we start to integrate a changeset, we need to do a bit of housekeeping
    # We never want to merge in:
    #   - merge tickets that describe merges from the local record

    # When we integrate changes, sometimes we will get handed changes we
    # already know about.
    #   - changes from local
    #   - changes from some other party we've merged from
    #   - merge tickets for the same
    # we'll want to skip or remove those changesets


    if (!  $self->should_accept_changeset($changeset) ){
        # if it's a changeset we don't care about, mark it as seen and move on
        $self->record_integration_of_changeset($changeset);
        $args{'reporting_callback'}->( changeset => $changeset, )
            if ( $args{'reporting_callback'} );
        return;
    }
    elsif ( my $conflict = $self->conflicts_from_changeset($changeset) ) {
        $self->log_debug( "Integrating conflicting changeset "
                . $changeset->original_sequence_no
                . " from "
                . $self->display_name_for_replica( $changeset->original_source_uuid ) );
        $args{conflict_callback}->($conflict) if $args{'conflict_callback'};
        $conflict->resolvers( [ sub { $args{resolver}->(@_) } ] ) if $args{resolver};
        if ( $args{resolver_class} ) {
            Prophet::App->require( $args{resolver_class} ) || die $@;
            $conflict->resolvers(
                [   sub {
                        $args{resolver_class}->new->run(@_);
                        }
                ]
            );
        }
        my $resolutions = $conflict->generate_resolution( $args{resdb} );

        #figure out our conflict resolution

        # IMPORTANT: these should be an atomic unit. dying here would be poor.
        # BUT WE WANT THEM AS THREE DIFFERENT CHANGESETS

        # integrate the nullification change
        $self->record_changes( $conflict->nullification_changeset );

        # integrate the original change
        $self->record_changeset_and_integration($changeset);

        # integrate the conflict resolution change
        $self->record_resolutions( $conflict->resolution_changeset );

        $args{'reporting_callback'}->(
            changeset => $changeset,
            conflict  => $conflict
        ) if ( $args{'reporting_callback'} );
        return 1;
    } else {
        $self->log_debug("Integrating changeset ".$changeset->original_sequence_no .
            " from " . $self->display_name_for_replica($changeset->original_source_uuid));
        $self->record_changeset_and_integration($changeset);
        $args{'reporting_callback'}->( changeset => $changeset ) if ( $args{'reporting_callback'} );
        return 1;
    }
}

=head3 record_changeset_and_integration L<Prophet::ChangeSet>

Given a L<Prophet::ChangeSet>, integrate each and every change within that
changeset into the handle's replica.

If the state handle is in the middle of an edit, the integration of this
changeset is recorded as part of that edit; if not, it is recorded as a new
edit.

=cut

sub record_changeset_and_integration {
    my $self      = shift;
    my $changeset = shift;

    $self->begin_edit(source => $changeset);
    $self->record_changes($changeset);

    $self->record_integration_of_changeset($changeset);

    $self->_set_original_source_metadata_for_current_edit($changeset);
    $self->commit_edit;

    return;
}

=head3 last_changeset_from_source $SOURCE_UUID

Returns the last changeset id seen from the replica identified by $SOURCE_UUID.

=cut

sub last_changeset_from_source {
    my $self = shift;
    my ($source) = validate_pos( @_, { type => SCALAR } );

    my $changeset_num =  $self->fetch_local_metadata('last-changeset-from-'.$source);
    # 0 is a valid changeset # 
    return defined $changeset_num ? $changeset_num : -1;
}


=head3 has_seen_changeset { source_uuid => <uuid>, sequence_no => <int> }

Returns true if we've previously integrated this changeset, even if we
originally received it from a different peer.

=cut

sub has_seen_changeset {
    my $self = shift;
    my %args = validate( @_, {source_uuid => 1, sequence_no => 1});
    $self->log_debug("Checking to see if we've ever seen changeset " .
        $args{sequence_no} . " from " .
        $self->display_name_for_replica($args{source_uuid}));

    # If the changeset originated locally, we never want it
    if ($args{source_uuid} eq $self->uuid ) {
        $self->log_debug("\t  - We have. (It originated locally.)");
        return 1 
    }
    # Otherwise, if the we have a merge ticket from the source, we don't want
    # the changeset if the source's sequence # is >= the changeset's sequence
    # #, we can safely skip it
    elsif ( $self->last_changeset_from_source( $args{source_uuid} ) >= $args{sequence_no} ) {
        $self->log_debug("\t  - We have seen this or a more recent changeset from remote.");
        return 1;
    } else {
        return undef;
    }
}

=head3 changeset_will_conflict L<Prophet::ChangeSet>

Returns true if any change that's part of this changeset won't apply cleanly to
the head of the current replica.

=cut

sub changeset_will_conflict {
    my $self = shift;
    my ($changeset) = validate_pos( @_, { isa => "Prophet::ChangeSet" } );

    return 1 if ( $self->conflicts_from_changeset($changeset) );

    return undef;
}

=head3 conflicts_from_changeset L<Prophet::ChangeSet>

Returns a L<Prophet::Conflict/> object if the supplied L<Prophet::ChangeSet/>
will generate conflicts if applied to the current replica.

Returns undef if the current changeset wouldn't generate a conflict.

=cut

sub conflicts_from_changeset {
    my $self = shift;
    my ($changeset) = validate_pos( @_, { isa => "Prophet::ChangeSet" } );
    require Prophet::Conflict;
    my $conflict = Prophet::Conflict->new( { changeset => $changeset,
                                             prophet_handle => $self} );

    $conflict->analyze_changeset();

    return undef unless $conflict->has_conflicting_changes;

    $self->log_debug("Conflicting changeset: ".JSON::to_json($conflict, {allow_blessed => 1}));

    return $conflict;
}

sub _check_db_uuids_on_merge {
    my $self = shift;
    my %args = validate( @_,
        {   for   => { isa => 'Prophet::Replica' },
            force => 0,
        });
    if (   $self->db_uuid && $args{for}->db_uuid
        && $self->db_uuid ne $args{for}->db_uuid ) {
        unless ( $args{'force'} ) {
            die "You are trying to merge two different databases! This is NOT\n"
                . "recommended. If you really want to do this,  add '--force' to\n"
                . "your commandline.\n\n"
                . "Local database:  "
                . $self->db_uuid . "\n"
                . "Remote database: "
                . $args{for}->db_uuid . "\n";
        }
    }
}

=head3 should_accept_changeset { from => L<Prophet::Replica>, changeset => L<Prophet::ChangeSet> }

Returns true if this replica hasn't yet seen the changeset C<changeset>.

=cut

sub should_accept_changeset {
    my $self = shift;
    my ($changeset) = validate_pos( @_, { changeset => { isa => 'Prophet::ChangeSet' } });


    $self->log_debug("Should I accept " .$changeset->original_sequence_no .
        " from ".$self->display_name_for_replica($changeset->original_source_uuid));
    return undef if (! $changeset->has_changes);
    return undef if ( $changeset->is_nullification || $changeset->is_resolution );
    return undef if $self->has_seen_changeset( sequence_no => $changeset->original_sequence_no,  source_uuid => $changeset->original_source_uuid );
    $self->log_debug("Yes, it has changes, isn't a nullification and I haven't seen it before");

    return 1;
}

=head3 fetch_changesets { after => SEQUENCE_NO }

Fetch all changesets from this replica after the local sequence number SEQUENCE_NO.

Returns a reference to an array of L<Prophet::ChangeSet/> objects.

See also L<traverse_changesets> for replica implementations to provide
streamly interface.

=cut

sub fetch_changesets {
    my $self = shift;
    my %args = validate( @_, { after => 1 } );
    my @results;

    $self->traverse_changesets( %args, callback => sub { my %args = @_; push @results, $args{changeset} } );

    return \@results;
}

=head2 methods to be implemented by a replica backend

=head3 uuid

Returns this replica's uuid.

=cut

sub uuid {}

=head3 latest_sequence_no

Returns the sequence # of the most recently committed changeset.

=cut

sub latest_sequence_no { return undef }

=head3 find_or_create_luid { uuid => UUID }

Finds or creates a LUID for the given UUID.

=cut

sub find_or_create_luid {
    my $self = shift;
    my %args = validate( @_, { uuid => 1 } );

    my $mapping = $self->_read_guid2luid_mappings;

    if (!exists($mapping->{ $args{'uuid'} })) {
        $mapping->{ $args{'uuid'} } = $self->_create_luid($mapping);
        $self->_write_guid2luid_mappings($mapping);
    }

    return $mapping->{ $args{'uuid'} };
}

sub find_luid_by_uuid {
    my $self = shift;
    my %args = validate( @_, { uuid => 1 } );
    my $mapping = $self->_read_guid2luid_mappings;

    if (!exists($mapping->{ $args{'uuid'} })) {
        return undef;
    }

    return $mapping->{ $args{'uuid'} };

}


=head3 find_uuid_by_luid { luid => LUID }

Finds the UUID for the given LUID. Returns C<undef> if the LUID is not known.

=cut

sub find_uuid_by_luid {
    my $self = shift;
    my %args = validate( @_, { luid => 1 } );

    my $mapping = $self->_read_luid2guid_mappings;
    return $mapping->{ $args{'luid'} };
}

=head3 _create_luid ( 'uuid' => 'luid' )

Given a UUID => LUID hash mapping, return a new unused LUID (one
higher than the mapping's current highest luid).

=cut

sub _create_luid {
    my $self = shift;
    my $map  = shift;

    return ++$map->{'_meta'}{'maximum_luid'};
}

=head3 _do_userdata_read $PATH $DEFAULT

Returns a reference to the parsed JSON contents of the file
given by C<$PATH> in the replica's userdata directory.

Returns C<$DEFAULT> if the file does not exist.

=cut

sub _do_userdata_read {
    my $self    = shift;
    my $path    = shift;
    my $default = shift;
    my $json = $self->read_userdata( path => $path ) || $default;
    require JSON;
    return JSON::from_json($json, { utf8 => 1 });
}

=head3 _do_userdata_write $PATH $VALUE

serializes C<$VALUE> to JSON and writes it to the file given by C<$PATH>
in the replica's userdata directory, creating parent directories as
necessary.

=cut

sub _do_userdata_write {
    my $self  = shift;
    my $path  = shift;
    my $value = shift;

    require JSON;
    my $content = JSON::to_json($value, { canonical => 1, pretty => 0, utf8 => 1 });

    $self->write_userdata(
        path    => $path,
        content => $content,
    );
}

=head3 _upstream_replica_cache_file

A string representing the name of the file where replica URLs that have been
previously pulled from are cached.

=cut

sub _upstream_replica_cache_file { "upstream-replica-cache" }

=head3 _read_cached_upstream_replicas

Returns a list of cached upstream replica URLs, or an empty list if
there are no cached URLs.

=cut

sub _read_cached_upstream_replicas {
    my $self = shift;
    return @{ $self->_do_userdata_read( $self->_upstream_replica_cache_file, '[]' ) || [] };
}

=head3 _write_cached_upstream_replicas @REPLICAS

writes the replica URLs given by C<@REPLICAS> to the upstream replica
cache file.

=cut

sub _write_cached_upstream_replicas {
    my $self     = shift;
    my @replicas = @_;
    return $self->_do_userdata_write( $self->_upstream_replica_cache_file, [@replicas] );
}

=head3 _guid2luid_file

The file in the replica's userdata directory which contains a serialized
JSON UUID => LUID hash mapping.

=cut

sub _guid2luid_file { "local-id-cache" }

=head3 _read_guid2luid_mappings

Returns a UUID => LUID hashref for this replica.

=cut

sub _read_guid2luid_mappings {
    my $self = shift;
    return $self->_do_userdata_read( $self->_guid2luid_file, '{}' );
}

=head3 _write_guid2luid_mappings ( 'uuid' => 'luid' )

Writes the given UUID => LUID hash map to C</_guid2luid_file> as serialized
JSON.

=cut

sub _write_guid2luid_mappings {
    my $self = shift;
    my $map  = shift;

    return $self->_do_userdata_write( $self->_guid2luid_file, $map );
}

=head3 _read_luid2guid_mappings

Returns a LUID => UUID hashref for this replica.

=cut

sub _read_luid2guid_mappings {
    my $self = shift;
    my $guid2luid = $self->_read_guid2luid_mappings(@_);
    delete $guid2luid->{'_meta'};
    my %luid2guid = reverse %$guid2luid;
    return \%luid2guid;
}

=head3 traverse_changesets { after => SEQUENCE_NO, until => SEQUENCE_NO, callback => sub { my %data = (changeset => undef, @_} }

Walk through each changeset in the replica after SEQUENCE_NO, calling the
C<callback> for each one in turn.

=cut

sub traverse_changesets {
    my $class = blessed($_[0]);
    Carp::confess "$class has failed to implement a 'traverse_changesets' method for their replica type.";
}

=head3 can_read_changesets

Returns true if this source is one we know how to read from (and have
permission to do so).

=cut

sub can_read_changesets { undef }

=head3 can_write_changesets

Returns true if this source is one we know how to write to (and have permission
to write to).

Returns false otherwise.

=cut

sub can_write_changesets { undef }

=head3 record_resolutions L<Prophet::ChangeSet>

Given a resolution changeset, record all the resolution changesets as well as
resolution records in the local resolution database.

Called ONLY on local resolution creation. (Synced resolutions are just synced
as records.)

=cut

sub record_resolutions {
    my $self       = shift;
    my ($changeset) = validate_pos(@_, { isa => 'Prophet::ChangeSet'});

    $self->_unimplemented("record_resolutions (since there is no writable handle)")
        unless ($self->can_write_changesets);

    # If we have a resolution db handle, record the resolutions there.
    # Otherwise, record them locally
    my $res_handle =  $self->resolution_db_handle || $self;

    return unless $changeset->has_changes;

    $self->begin_edit(source => $changeset);
    $self->record_changes($changeset);
    $res_handle->_record_resolution($_) for $changeset->changes;
    $self->commit_edit();
}

=head3 _record_resolution L<Prophet::Change>

Called ONLY on local resolution creation. (Synced resolutions are just synced
as records.)

=cut

sub _record_resolution {
    my $self      = shift;
    my ($change) = validate_pos(@_, { isa => 'Prophet::Change'});

    return 1 if $self->record_exists(
        uuid => $self->uuid,
        type => '_prophet_resolution-' . $change->resolution_cas
    );

    $self->create_record(
        uuid  => $self->uuid,
        type  => '_prophet_resolution-' . $change->resolution_cas,
        props => {
            _meta => $change->change_type,
            map { $_->name => $_->new_value } $change->prop_changes
        }
    );
}

=head2 routines dealing with integrating changesets into a replica

=head3 record_changes L<Prophet::ChangeSet>

Inside an edit (transaction), integrate all changes in this changeset
and then call the _after_record_changes() hook.

=cut

sub record_changes {
    my $self      = shift;
    my ($changeset) = validate_pos(@_, { isa => 'Prophet::ChangeSet'});
    $self->_unimplemented ('record_changes') unless ($self->can_write_changesets);
    eval {
        local $SIG{__DIE__} = 'DEFAULT';
        my $inside_edit = $self->current_edit ? 1 : 0;
        $self->begin_edit(source => $changeset) unless ($inside_edit);
        $self->integrate_changes($changeset);
        $self->_after_record_changes($changeset);
        $self->commit_edit() unless ($inside_edit);
    };
    die($@) if ($@);
}

=head3 integrate_changes L<Prophet::ChangeSet>

This routine is called by L</record_changes> with a L<Prophet::ChangeSet>
object. It integrates all changes from that object into the current replica.

All bookkeeping, such as opening and closing an edit, is done by
L</record_changes>.

If your replica type needs to play games to integrate multiple changes as a
single record, this is what you'd override.

=cut

sub integrate_changes {
    my ($self, $changeset) = validate_pos( @_, {isa => 'Prophet::Replica'},
                                          { isa => 'Prophet::ChangeSet' } );
    $self->integrate_change($_, $changeset) for ( $changeset->changes );

}

=head2 integrate_change L<Prophet::Change> <Prophet::ChangeSet>

Integrates the given change into the current replica. Used in
L</integrate_changes>.

=cut

sub integrate_change {
    my ($self, $change) = validate_pos(@_, { isa => 'Prophet::Replica' },
                                           { isa => 'Prophet::Change' }, 
                                           { isa => 'Prophet::ChangeSet' } 
);

    my %new_props = map { $_->name => $_->new_value } $change->prop_changes;
    if ( $change->change_type eq 'add_file' ) {
        $self->log_debug("add_file: " .$change->record_type. " " .$change->record_uuid);
        $self->create_record( type  => $change->record_type, uuid  => $change->record_uuid, props => \%new_props);
    } elsif ( $change->change_type eq 'add_dir' ) {
        $self->log_debug("(IGNORED) add_dir: " .$change->record_type. " " .$change->record_uuid);
    } elsif ( $change->change_type eq 'update_file' ) {
        $self->log_debug("update_file: " .$change->record_type. " " .$change->record_uuid);
        $self->set_record_props( type  => $change->record_type, uuid  => $change->record_uuid, props => \%new_props);
    } elsif ( $change->change_type eq 'delete' ) {
        $self->log_debug("delete_file: " .$change->record_type. " " .$change->record_uuid);
        $self->delete_record( type => $change->record_type, uuid => $change->record_uuid);
    } else {
        Carp::confess( "Unknown change type: " . $change->change_type );
    }
}

=head3 record_integration_of_changeset L<Prophet::ChangeSet>

This routine records the immediately upstream and original source
uuid and sequence numbers for this changeset. Prophet uses this
data to make sane choices about later replay and merge operations

=cut

sub record_integration_of_changeset {
    my $self = shift;
    my ($changeset) = validate_pos( @_, { isa => 'Prophet::ChangeSet' } );

    if ( $changeset->original_source_uuid ne $self->uuid
        && ( $self->last_changeset_from_source( $changeset->original_source_uuid ) < $changeset->original_sequence_no )
        ) {
        $self->record_last_changeset_from_replica(
            $changeset->original_source_uuid => $changeset->original_sequence_no );
    }
    if ( $changeset->source_uuid ) {
        if ( $self->last_changeset_from_source( $changeset->source_uuid ) < $changeset->sequence_no ) {
            $self->record_last_changeset_from_replica( $changeset->source_uuid => $changeset->sequence_no );
        }
    }
}

sub record_last_changeset_from_replica {
    my $self = shift;
    my ($uuid, $sequence) = validate_pos(@_, 1,1);
        return $self->store_local_metadata( 'last-changeset-from-' . $uuid => $sequence );

}

=head2 routines which need to be implemented by any Prophet backend store

=head3 uuid

Returns this replica's UUID.

=head3 create_record { type => $TYPE, uuid => $UUID, props => { key-value pairs } }

Create a new record of type C<$TYPE> with uuid C<$UUID> within the current
replica.

Sets the record's properties to the key-value hash passed in as the C<props>
argument.

If called from within an edit, it uses the current edit. Otherwise it
manufactures and finalizes one of its own.

=head3 delete_record {uuid => $UUID, type => $TYPE }

Deletes the record C<$UUID> of type C<$TYPE> from the current replica. 

Manufactures its own new edit if C<$self->current_edit> is undefined.

=head3 set_record_props { uuid => $UUID, type => $TYPE, props => {hash of kv pairs }}

Updates the record of type C<$TYPE> with uuid C<$UUID> to set each property
defined by the props hash. It does NOT alter any property not defined by the
props hash.

Manufactures its own current edit if none exists.

=head3 get_record_props { uuid => $UUID, type => $TYPE, root => $ROOT }

Returns a hashref of all properties for the record of type C<$TYPE> with uuid
C<$UUID>.

'root' is an optional argument which you can use to pass in an alternate
historical version of the replica to inspect.  Code to look at the immediately
previous version of a record might look like:

    $handle->get_record_props(
        type => $record->type,
        uuid => $record->uuid,
        root => $self->repo_handle->fs->revision_root( $self->repo_handle->fs->youngest_rev - 1 )
    );

=head3 record_exists {uuid => $UUID, type => $TYPE, root => $ROOT }

Returns true if the record in question exists and false otherwise.

=head3 list_records { type => $TYPE }

Returns a reference to a list of all the records of type $TYPE.

=head3 list_records

Returns a reference to a list of all the known types in your Prophet database.

=head3 type_exists { type => $type }

Returns true if we have any records of type C<$TYPE>.

=head2 routines which need to be implemented by any _writable_ prophet backend store

=head2 optional routines which are provided for you to override with backend-store specific behaviour

=head3 _after_record_changes L<Prophet::ChangeSet>

Called after the replica has integrated a new changeset but before closing the
current transaction/edit.

The SVN backend, for example, used this to record author metadata about this
changeset.

=cut

sub _after_record_changes {
    return 1;
}

=head3 _set_original_source_metadata_for_current_edit

Sets C<original_source_uuid> and C<original_sequence_no> for the current edit.

=cut

sub _set_original_source_metadata_for_current_edit  {}

=head2 helper routines

=cut

=head3 log $MSG

Logs the given message to C<STDERR> (but only if the C<PROPHET_DEBUG>
environmental variable is set).

=cut

sub log {
    my $self = shift;
    my ($msg) = validate_pos(@_, 1);
    Carp::confess unless ($self->app_handle);
    $self->app_handle->log($msg);
}

sub log_debug { 
    my $self = shift;
    my $msg = shift;
    $self->app_handle->log_debug($self->display_name_for_replica.": " .$msg);
}

=head2 log_fatal $MSG

Logs the given message and dies with a stack trace.

=cut

sub log_fatal {
    my $self = shift;

    # always skip this fatal_error function when generating a stack trace
    local $Carp::CarpLevel = $Carp::CarpLevel + 1;
    if ( eval {$self->app_handle }) {
        $self->app_handle->log_fatal(@_);
    } else {
        die join('',@_) ."\n";
    }
}

=head2 changeset_creator

The string to use as the creator of a changeset.

=cut

sub changeset_creator {
    my $self = shift;
    return $self->app_handle->current_user_email;
}

=head2 display_name_for_replica [uuid]

If the user has a "friendly" name for this replica, then use it. Otherwise,
display the replica's uuid.

If you pass in a uuid, it will be used instead of the replica's uuid.

=cut

sub display_name_for_replica {
    my $self = shift;
    my $uuid = shift || $self->uuid;

    return $uuid if !$self->app_handle;

    return $self->app_handle->display_name_for_replica($uuid);
}

__PACKAGE__->meta->make_immutable();
no Any::Moose;

1;
