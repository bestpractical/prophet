use warnings;
use strict;

package Prophet::Replica;
use base qw/Class::Accessor/;
use Params::Validate qw(:all);
use UNIVERSAL::require;


__PACKAGE__->mk_accessors(qw(state_handle resolution_db_handle is_resdb is_state_handle db_uuid url));

use constant state_db_uuid => 'state';
use Module::Pluggable search_path => 'Prophet::Replica', sub_name => 'core_replica_types', require => 0, except => qr/Prophet::Replica::(.*)::/;

our $REPLICA_TYPE_MAP = {};
our $MERGETICKET_METATYPE = '_merge_tickets';

 for ( __PACKAGE__->core_replica_types) {
    $_->require; # Require here, rather than with the autorequire from Module::Pluggable as that goes too far
    # and tries to load Prophet::Replica::SVN::ReplayEditor;
    __PACKAGE__->register_replica_scheme(scheme => $_->scheme, class => $_) 
 }
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

    return unless $self->resolution_db_handle;
    return unless $source->resolution_db_handle;

    $self->resolution_db_handle->import_changesets(
        from     => $source->resolution_db_handle,
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


        $self->log("Considering changeset ".$changeset->original_sequence_no .  " from " . substr($changeset->original_source_uuid,0,6));

    # when we start to integrate a changeset, we need to do a bit of housekeeping
    # We never want to merge in:
    # merge tickets that describe merges from the local record

    # When we integrate changes, sometimes we will get handed changes we already know about.
    #   - changes from local
    #   - changes from some other party we've merged from
    #   - merge tickets for the same
    # we'll want to skip or remove those changesets

    return if $changeset->original_source_uuid eq $self->uuid;
    return if ($changeset->is_nullification);

    $self->remove_redundant_data($changeset);    #Things we have already seen
    return if ($changeset->is_empty);



    if ( my $conflict = $self->conflicts_from_changeset($changeset) ) {
        $self->log("Integrating conflicting changeset ".$changeset->original_sequence_no .  " from " . substr($changeset->original_source_uuid,0,6));
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
        $self->record_changes( $conflict->nullification_changeset );

        # integrate the original change
        $self->record_changeset_and_integration($changeset);

        # integrate the conflict resolution change
        $self->record_resolutions( $conflict->resolution_changeset );

        $args{'reporting_callback'}->( changeset => $changeset, conflict => $conflict ) if ( $args{'reporting_callback'} );

    } else {
        $self->log("Integrating changeset ".$changeset->original_sequence_no .  " from " . substr($changeset->original_source_uuid,0,6));
        $self->record_changeset_and_integration($changeset);
        $args{'reporting_callback'}->( changeset => $changeset ) if ( $args{'reporting_callback'} );

    }
}

=head2 integrate_changeset L<Prophet::ChangeSet>

Given a L<Prophet::ChangeSet>, integrates each and every change within that changeset into the handle's replica.

This routine also records that we've seen this changeset (and hence everything before it) from both the peer who sent it to us AND the replica who originally created it.

=cut



=head2 record_changeset_and_integration

=cut

sub record_changeset_and_integration {
    my $self      = shift;
    my $changeset = shift;

    $self->begin_edit;
    $self->record_changes($changeset);

    my $state_handle = $self->state_handle;
    my $inside_edit = $state_handle->current_edit ? 1 : 0;

    $state_handle->begin_edit() unless ($inside_edit);
    $state_handle->record_integration_of_changeset($changeset);
    $state_handle->commit_edit() unless ($inside_edit);
    $self->_set_original_source_metadata_for_current_edit($changeset);
    $self->commit_edit;
    

    return;
}
=head2 last_changeset_from_source $SOURCE_UUID

Returns the last changeset id seen from the source identified by $SOURCE_UUID

=cut

sub last_changeset_from_source {
    my $self = shift;
    my ($source) = validate_pos( @_, { type => SCALAR } );

    my $last =  $self->state_handle->_retrieve_metadata_for( $MERGETICKET_METATYPE, $source, 'last-changeset' ) || 0;
    return $last;
}


=head2 has_seen_changeset Prophet::ChangeSet

Returns true if we've previously integrated this changeset, even if we originally recieved it from a different peer

=cut

sub has_seen_changeset {
    my $self = shift;
    my ($changeset) = validate_pos( @_, { isa => "Prophet::ChangeSet" } );

    $self->log("Checking to see if we've ever seen changeset " .$changeset->original_sequence_no . " from ".substr($changeset->original_source_uuid,0,6));

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

    my $conflict = Prophet::Conflict->new( { changeset => $changeset, prophet_handle => $self} );

    $conflict->analyze_changeset();

    return undef unless @{ $conflict->conflicting_changes };

    return $conflict;

}

sub remove_redundant_data {
    my ( $self, $changeset ) = @_;


    my @new_changes;
    foreach my $change ($changeset->changes) {
            # when would we run into resolution records in a nonresb? XXX
            next if ($change->record_type eq '_prophet_resolution' && !$self->is_resdb); 

            # never integrate a merge ticket that comes from a foriegn database.
            # implict merge tickets are the devil and are lies. Merge tickets are always generated locally
            # by importing a change that originated on that replica
            # (The actual annoying technical problem is that the locally created merge ticket is written out in a separate transaction 
            # at ~ the same time as the original imported one is being written.
            # This makes svn go boom
            next if( $change->record_type eq $MERGETICKET_METATYPE);# && $change->record_uuid eq $self->uuid );
            push (@new_changes, $change);
    }
    
    $changeset->changes(\@new_changes);

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


    $self->log("Evaluating changesets to apply to ".substr($args{'for'}->uuid,0,6). " starting with ".  $args{for}->last_changeset_from_source( $self->uuid ));


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
    
    $self->log("Should I send " .$args{changeset}->original_sequence_no . " from ".substr($args{changeset}->original_source_uuid,0,6) . " to " .substr($args{'to'}->uuid, 0, 6));

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

=head2 export_to { path => $PATH } 

This routine will export a copy of this prophet database replica to a flat file on disk suitable for 
publishing via HTTP or over a local filesystem for other Prophet replicas to clone or incorporate changes from.

See C<Prophet::ReplicaExporter>

=cut

sub export_to {
    my $self = shift;
    my %args = validate( @_, { path => 1, } );
    Prophet::ReplicaExporter->require();

    my $exporter = Prophet::ReplicaExporter->new({target_path => $args{'path'}, source_replica => $self});
    $exporter->export();
}


=head1 methods to be implemented by a replica backend



=cut


=head2 uuid 

Returns this replica's uuid

=cut

sub uuid {}

=head2 latest_sequence_no

Returns the sequence # of the most recently committed changeset

=cut

sub latest_sequence_no {return undef }

=head2 traverse_changesets { after => SEQUENCE_NO, callback => sub {} }

Walk through each changeset in the replica after SEQUENCE_NO, calling the C<callback> for each one in turn.


=cut

sub traverse_changesets {

    Carp::confess "Someone has failed to implement a 'traverse_changesets' method for their replica type.";


}
=head2  can_write_changesets

Returns true if this source is one we know how to write to (and have permission to write to)

Returns false otherwise

=cut

sub can_read_records { undef }
sub can_write_records { undef }
sub can_read_changesets { undef }
sub can_write_changesets { undef } 



=head1 CODE BELOW THIS LINE USED TO BE IN HANDLE




=head2 record_resolutions Prophet::ChangeSet

Given a resolution changeset

record all the resolution changesets as well as resolution records in the local resolution database;

Called ONLY on local resolution creation. (Synced resolutions are just synced as records)

=cut

sub record_resolutions {
    my $self       = shift;
    my ($changeset) = validate_pos(@_, { isa => 'Prophet::ChangeSet'});
        $self->_unimplemented("record_resolutions (since there is no writable handle)") unless ($self->can_write_changesets);
        # If we have a resolution db handle, record the resolutions there.
        # Otherwise, record them locally
    my $res_handle =  $self->resolution_db_handle || $self;

    return unless $changeset->changes;

    $self->begin_edit();
    $self->record_changes($changeset);
    $res_handle->_record_resolution($_) for $changeset->changes;
    $self->commit_edit();
}
=head2 _record_resolution Prophet::Change
 
Called ONLY on local resolution creation. (Synced resolutions are just synced as records)

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

=head1 Routines dealing with integrating changesets into a replica

=head2 record_changes Prophet::ChangeSet

Inside an edit (transaction), integrate all changes in this transaction
and then call the _after_record_changes() hook

=cut

sub record_changes {
    my $self      = shift;
    my ($changeset) = validate_pos(@_, { isa => 'Prophet::ChangeSet'});
    $self->_unimplemented ('record_changes') unless ($self->can_write_changesets);
    eval {
        my $inside_edit = $self->current_edit ? 1 : 0;
        $self->begin_edit() unless ($inside_edit);
        $self->_integrate_change($_) for ( $changeset->changes );
        $self->_after_record_changes($changeset);
        $self->commit_edit() unless ($inside_edit);
    };
    die($@) if ($@);
}

sub _integrate_change {
    my $self   = shift;
    my ($change) = validate_pos(@_, { isa => 'Prophet::Change'});

    my %new_props = map { $_->name => $_->new_value } $change->prop_changes;
    if ( $change->change_type eq 'add_file' ) {
        $self->log("add_file: " .$change->record_type. " " .$change->record_uuid);
        $self->create_record( type  => $change->record_type, uuid  => $change->record_uuid, props => \%new_props);
    } elsif ( $change->change_type eq 'add_dir' ) {
        $self->log("(IGNORED) add_dir: " .$change->record_type. " " .$change->record_uuid);
    } elsif ( $change->change_type eq 'update_file' ) {
        $self->log("update_file: " .$change->record_type. " " .$change->record_uuid);
        $self->set_record_props( type  => $change->record_type, uuid  => $change->record_uuid, props => \%new_props);
    } elsif ( $change->change_type eq 'delete' ) {
        $self->log("delete_file: " .$change->record_type. " " .$change->record_uuid);
        $self->delete_record( type => $change->record_type, uuid => $change->record_uuid);
    } else {
        Carp::confess( " I have never heard of the change type: " . $change->change_type );
    }

}
=head2 record_integration_of_changeset L<Prophet::ChangeSet>

This routine records the immediately upstream and original source
uuid and sequence numbers for this changeset. Prophet uses this
data to make sane choices about later replay and merge operations


=cut
sub record_integration_of_changeset {
    my $self = shift;
    my ($changeset) = validate_pos( @_, { isa => 'Prophet::ChangeSet' } );

    # Record a merge ticket for the changeset's "original" source
    return $self->_record_metadata_for( $MERGETICKET_METATYPE, $changeset->original_source_uuid, 'last-changeset', $changeset->original_sequence_no );

}


=head1 metadata storage routines 

=cut 
=head2 metadata_storage $RECORD_TYPE, $PROPERTY_NAME

Returns a function which takes a UUID and an optional value to get (or set) metadata rows in a metadata table.
We use this to record things like merge tickets


=cut
sub metadata_storage {
    my $self = shift;
    my ( $type, $prop_name ) = validate_pos( @_, 1, 1 );
    return sub {
        my $uuid = shift;
        if (@_) {
            return $self->_record_metadata_for( $type, $uuid, $prop_name, @_ );
        }
        return $self->_retrieve_metadata_for( $type, $uuid, $prop_name );

    };
}

sub _retrieve_metadata_for {
    my $self = shift;
    my ( $name, $source_uuid, $prop_name ) = validate_pos( @_, 1, 1, 1 );

    my $entry = Prophet::Record->new( handle => $self, type => $name );
    unless ( $entry->load( uuid => $source_uuid )) {
            return undef;    
    }

    return $entry->prop($prop_name);

}

sub _record_metadata_for {
    my $self = shift;
    my ( $name, $source_uuid, $prop_name, $content )
        = validate_pos( @_, 1, 1, 1, 1 );
    $self->log( "Storing $content in $prop_name for $name " . substr( $source_uuid, 0, 6 ) );

    if ( !$self->record_exists( type => $name, uuid => $source_uuid ) ) {
        $self->log( "I don't have a $name for " . substr( $source_uuid, 0, 6 ) . "Creating it" );
        $self->create_record(
            uuid => $source_uuid,
            type => $name, props => { $prop_name => $content }
        );
    } else {
        $self->log( "Setting $prop_name to $content for $name for " . substr( $source_uuid, 0, 6 ) );
        $self->set_record_props(
            uuid  => $source_uuid,
            type  => $name,
            props => { $prop_name => $content }
        );
    }
}


=head1 The following functions need to be implemented by any Prophet backing store.

=head2 uuid

Returns this replica's UUID

=head2 create_record { type => $TYPE, uuid => $uuid, props => { key-value pairs }}

Create a new record of type C<$type> with uuid C<$uuid>  within the current replica.

Sets the record's properties to the key-value hash passed in as the C<props> argument.

If called from within an edit, it uses the current edit. Otherwise it manufactures and finalizes one of its own.



=head2 delete_record {uuid => $uuid, type => $type }

Deletes the record C<$uuid> of type C<$type> from the current replica. 

Manufactures its own new edit if C<$self->current_edit> is undefined.

=head2 set_record_props { uuid => $uuid, type => $type, props => {hash of kv pairs }}


Updates the record of type C<$type> with uuid C<$uuid> to set each property defined by the props hash. It does NOT alter any property not defined by the props hash.

Manufactures its own current edit if none exists.


=head2 get_record_props {uuid => $uuid, type => $type, root => $root }

Returns a hashref of all properties for the record of type $type with uuid C<$uuid>.

'root' is an optional argument which you can use to pass in an alternate historical version of the replica to inspect.  Code to look at the immediately previous version of a record might look like:

    $handle->get_record_props(
        type => $record->type,
        uuid => $record->uuid,
        root => $self->repo_handle->fs->revision_root( $self->repo_handle->fs->youngest_rev - 1 )
    );

=head2 record_exists {uuid => $uuid, type => $type, root => $root }

Returns true if the record in question exists. False otherwise


=head2 list_records { type => $type }

Returns a reference to a list of all the records of type $type

=head2 list_records

Returns a reference to a list of all the known types in your Prophet database


=head2 type_exists { type => $type }

Returns true if we have any records of type C<$type>



=cut
=head2 The following functions need to be implemented by any _writable_ prophet backing store

=cut
=head2 The following optional routines are provided for you to override with backing-store specific behaviour


=head3 _after_record_changes Prophet::ChangeSet

Called after the replica has integrated a new changeset but before closing the current transaction/edit.

The SVN backend, for example, uses this to record author metadata about this changeset.

=cut
sub _after_record_changes {
    return 1;
}

sub _set_original_source_metadata_for_current_edit  {}


sub log {
    my $self = shift;
    my ($msg) = validate_pos(@_, 1);
    print STDERR "# ".substr($self->uuid,0,6)." (".$self->scheme.":".$self->url." )".": " .$msg."\n" if ($ENV{'PROPHET_DEBUG'});
}


1;

