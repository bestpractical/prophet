package Prophet::Replica::sqlite;
use Any::Moose;
extends 'Prophet::Replica';
use Params::Validate qw(:all);
use File::Spec  ();
use Data::UUID;
use File::Path;
use Prophet::Util;
use DBI;

has dbh => (
    is => 'rw',
    isa     => 'DBI::db',
    lazy => 1,
    default => sub {
        my $self = shift;
        DBI->connect( "dbi:SQLite:" . $self->db_file , undef, undef, {RaiseError =>1, AutoCommit => 1 });
     }


    );

sub db_file { shift->fs_root ."/db.sqlite"}

has '+db_uuid' => (
    lazy    => 1,
    default => sub { shift->fetch_local_metadata('database-uuid') },
);

has _uuid => ( is => 'rw', );

has _replica_version => (
    is      => 'rw',
    isa     => 'Int',
    lazy    => 1,
    default => sub { shift->fetch_local_metadata('replica-version') || 0 }
);

has fs_root_parent => (
    is      => 'rw',
    lazy    => 1,
    default => sub {
        my $self = shift;
        return $self->url =~ m{^(?:sqlite\:)?file://(.*)/.*?$} ? $1 : undef;
    }
);

has fs_root => (
    is      => 'rw',
    lazy    => 1,
    default => sub {
        my $self = shift;
        return $self->url =~ m{^(?:sqlite\:)?file://(.*)$} ? $1 : undef;
    },
);

has current_edit => ( is => 'rw', );

has current_edit_records => (
    is        => 'rw',
    isa       => 'ArrayRef',
    default   => sub { [] },
);

has '+resolution_db_handle' => (
    isa     => 'Prophet::Replica | Undef',
    lazy    => 1,
    default => sub {
        my $self = shift;
        return if $self->is_resdb ;
        return Prophet::Replica->get_handle(
            {   url        => $self->url . '/resolutions',
                app_handle => $self->app_handle,
                is_resdb   => 1,
            }
        );
    },
);

our $PROP_CACHE;

use constant scheme   => 'sqlite';
use constant userdata_dir    => 'userdata';
sub BUILD {
    my $self = shift;
    my $args = shift;
    Carp::cluck() unless ( $args->{app_handle} );
    for ( $self->{url} ) {
        #s/^sqlite://;    # url-based constructor in ::replica should do better
        s{/$}{};
    }
   $self->_check_for_upgrades if ($self->replica_exists);
        

}

sub _check_for_upgrades {
    my $self = shift;
   if  ( $self->replica_version && $self->replica_version < 2) {
        $self->_upgrade_replica_to_v2();
   } 

}




sub __fetch_data {
    my $self = shift;
    my $table = shift;
    my $key = shift;

    my $sth = $self->dbh->prepare("SELECT value FROM $table WHERE key = ?");
    $sth->execute($key);
       
    my $results = $sth->fetchrow_arrayref;
    return $results?$results->[0] : undef;
}

sub __store_data {
    my $self = shift;
    my %args = ( key => undef, value => undef, table => undef, @_);
    $self->dbh->do("DELETE FROM $args{table} WHERE key = ?", {},$args{key});
    $self->dbh->do("INSERT INTO $args{table} (key,value) VALUES(?,?)", {}, $args{key}, $args{value});
    
}

sub fetch_local_metadata {
    my $self = shift;
    my $key = shift;
    return $self->__fetch_data( 'local_metadata', $key );
}

sub store_local_metadata {
    my $self = shift;
    my ($key, $value) = (@_);
    $self->__store_data( table => 'local_metadata', key => $key, value => $value);
}

sub _fetch_userdata {
    my $self = shift;
    my $key = shift;
    return $self->__fetch_data( 'userdata', $key );
}

sub _store_userdata {
    my $self = shift;
    $self->__store_data( table => 'userdata', @_ );
}

=head2 replica_exists

Returns true if the replica already exists / has been initialized.
Returns false otherwise.

=cut

sub replica_exists {
    my $self = shift;
    return -f $self->db_file ? 1 : 0;
}

=head2 replica_version

Returns this replica's version.

=cut

sub replica_version { die "replica_version is read-only; you want set_replica_version." if @_ > 1; shift->_replica_version }

=head2 set_replica_version

Sets the replica's version to the given integer.

=cut

sub set_replica_version {
    my $self    = shift;
    my $version = shift;

    $self->_replica_version($version);

    $self->store_local_metadata( 'replica-version' => $version,);

    return $version;
}

sub can_initialize {
    my $self = shift;
    if ( $self->fs_root_parent && -w $self->fs_root_parent ) {
        return 1;

    }
    return 0;
}

use constant can_read_records    => 1;
use constant can_read_changesets => 1;
sub can_write_changesets {1}
sub can_write_records    {1}

sub initialize {
    my $self = shift;
    my %args = validate(
        @_,
        {
            db_uuid    => 0,
            resdb_uuid => 0,
        }
    );

    if ( !$self->fs_root_parent ) {

        if ( $self->can_write_changesets ) {
            die "We can only create local prophet replicas. It looks like you're trying to create "
              . $self->url;
        }
        else {
            die "Prophet couldn't find a replica at \""
              . $self->url
              . "\"\n\n"
              . "Please check the URL and try again.\n";

        }
    }

    return if $self->replica_exists;
    mkpath( [ $self->fs_root ] );

    #$self->dbh->begin_work;
    for (

        q{
CREATE TABLE records (
    luid INTEGER PRIMARY KEY AUTOINCREMENT,
    uuid text,
    type text
)
},
        q{
CREATE TABLE record_props (
    uuid text,
    prop text,
    value text 
)

}, q{
CREATE TABLE changesets (
    sequence_no INTEGER PRIMARY KEY AUTOINCREMENT,
    creator text,
    created text,
    is_nullification boolean,
    is_resolution boolean,

    original_source_uuid text,
    original_sequence_no INTEGER
)
}, q{
CREATE TABLE changes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    record text,
    changeset integer, 
    change_type text,
    record_type text
)
}, q{
CREATE TABLE prop_changes (
    change integer,
    name text,
    old_value text,
    new_value text
)
}, q{
CREATE TABLE local_metadata (
    key text,
    value text

)
}, q{
CREATE TABLE userdata (
    key text,
    value text
)
},

        q{create index uuid_idx on record_props(uuid)},
        q{create index typeuuuid on records(type, uuid)},
        q{create index keyidx on userdata(key)}

      )
    {
        $self->dbh->do($_) || warn $self->dbh->errstr;
    }

    $self->set_db_uuid( $args{'db_uuid'} || Data::UUID->new->create_str );
    $self->set_replica_uuid( Data::UUID->new->create_str );
    $self->set_replica_version(2);
    $self->resolution_db_handle->initialize( db_uuid => $args{resdb_uuid} )
      if !$self->is_resdb;
    $self->after_initialize->($self);
}

sub latest_sequence_no {
    my $self = shift;

    my $sth = $self->dbh->prepare("SELECT MAX(sequence_no) FROM changesets");
    $sth->execute();
    return $sth->fetchrow_array || 0;
}

=head2 uuid

Return the replica  UUID

=cut

sub uuid {
    my $self = shift;
    $self->_uuid( $self->fetch_local_metadata('replica-uuid') ) unless $self->_uuid;
    return $self->_uuid;
}

sub set_replica_uuid {
    my $self = shift;
    my $uuid = shift;
    $self->store_local_metadata( 'replica-uuid' => $uuid);

}

sub set_db_uuid {
    my $self = shift;
    my $uuid = shift;
    $self->store_local_metadata( 'database-uuid', => $uuid);
    $self->SUPER::set_db_uuid($uuid);
};

=head1 Internals of record handling

=cut

sub _write_record {
    my $self   = shift;
    my %args   = validate( @_, { record => { isa => 'Prophet::Record' }, } );
    my $record = $args{'record'};

    $self->_write_record_to_db(
        type  => $record->type,
        uuid  => $record->uuid,
        props => $record->get_props,
    );
}

sub _write_record_to_db {
    my $self = shift;
    my %args = validate( @_, { type => 1, uuid => 1, props => 1 } );

    for ( keys %{ $args{'props'} } ) {
        delete $args{'props'}->{$_}
            if ( !defined $args{'props'}->{$_} || $args{'props'}->{$_} eq '' );
    }

    if ($self->record_exists( uuid => $args{uuid}, type => $args{type} ) ) {
        $self->_delete_record_props_from_db( uuid => $args{uuid} ) 
    } else {
        $self->dbh->do( "INSERT INTO records (type, uuid) VALUES (?,?)", {},
        $args{type}, $args{uuid} );

    }
    $self->dbh->do(
        "INSERT INTO record_props (uuid, prop, value) VALUES (?,?,?)", {},
        $args{uuid}, $_, $args{props}->{$_} )
    for ( keys %{ $args{props} } );

}

sub _delete_record_from_db {
    my $self = shift;
    my %args = validate( @_, { uuid => 1 } );

    $self->dbh->do("DELETE FROM records where uuid = ?", {},$args{uuid});
    $self->_delete_record_props_from_db(%args);
}

sub _delete_record_props_from_db {
    my $self = shift;
    my %args = validate( @_, { uuid => 1 } );

    $self->dbh->do("DELETE FROM record_props where uuid = ?", {}, $args{uuid});
    delete $PROP_CACHE->{$args{uuid}};

}

=head2 traverse_changesets { after => SEQUENCE_NO, UNTIL => SEQUENCE_NO, callback => sub { } } 

Walks through all changesets from $after to $until, calling $callback on each.

If no $until is specified, the latest changeset is assumed.

=cut

sub traverse_changesets {
    my $self = shift;
    my %args = validate(
        @_,
        {   after    => 1,
            callback => 1,
            until    => 0,
        }
    );

    my $first_rev = ( $args{'after'} + 1 ) || 1;
    my $latest = $self->latest_sequence_no;

    if ( defined $args{until} && $args{until} < $latest) {
            $latest = $args{until};
    }

    $self->log_debug("Traversing changesets between $first_rev and $latest");
    for my $rev ( $first_rev .. $latest ) {
        $self->log_debug("Fetching changeset $rev");
        my $changeset = $self->_load_changeset_from_db( sequence_no => $rev,);
        $args{callback}->($changeset);
    }
}

=head2 changesets_for_record { uuid => $uuid, type => $type }

Returns an ordered set of changeset objects for all changesets containing
changes to this object. 

Note that changesets may include changes to other records

=cut

sub changesets_for_record {
    my $self = shift;
    my %args = validate( @_, { uuid => 1, type => 1 } );

    my $sth = $self->dbh->prepare( "SELECT DISTINCT changesets.* "
            . "FROM changes, changesets "
            . "WHERE  changesets.sequence_no = changes.changeset "
            . "AND changes.record = ?"
        );

    require Prophet::ChangeSet;
    $sth->execute( $args{uuid} );

    my @changesets;

    while ( my $cs = $sth->fetchrow_hashref() ) {
        push @changesets, $self->_instantiate_changeset_from_db($cs);

    }
    return @changesets;
}

sub _load_changeset_from_db {
    my $self = shift;
    my %args = validate( @_, {   sequence_no          => 1 });


    my $sth = $self->dbh->prepare("SELECT creator, created, sequence_no, ".
                                  "original_source_uuid, original_sequence_no, ".
                                  "is_nullification, is_resolution from changesets ".
                                  "WHERE sequence_no = ?");
            $sth->execute($args{sequence_no});


    my $data = $sth->fetchrow_hashref;
    return $self->_instantiate_changeset_from_db($data);
}

sub _instantiate_changeset_from_db {
    my $self = shift;
    my $data = shift;
    require Prophet::ChangeSet;
    my $changeset = Prophet::ChangeSet->new(%$data, source_uuid => $self->uuid );

    
    my $sth = $self->dbh->prepare("SELECT id, record, change_type, record_type from changes WHERE changeset = ?");
    $sth->execute($changeset->sequence_no);
    while (my $row = $sth->fetchrow_hashref) {
        my $change_id = delete $row->{id};
        my $record_type = delete $row->{record_type};

        my $change = Prophet::Change->new( record_uuid => $row->{record},
                change_type => $row->{change_type}, record_type => $record_type );
        my $propchange_sth = $self->dbh->prepare("SELECT name, old_value, new_value FROM prop_changes WHERE change = ?");
        $propchange_sth->execute($change_id);
        while (my $pc = $propchange_sth->fetchrow_hashref) {
            $change->add_prop_change( name => $pc->{name}, old => $pc->{old_value}, new => $pc->{new_value});
        }
        push @{$changeset->changes}, $change;
    }

    return $changeset;
}

sub begin_edit {
    my $self = shift;
    my %args = validate( @_, {   source => 0,    # the changeset that we're replaying, if applicable
        });

    my $source = $args{source};

    my $creator = $source ? $source->creator : $self->changeset_creator;
    my $created = $source && $source->created;

    require Prophet::ChangeSet;
    my $changeset = Prophet::ChangeSet->new( {   source_uuid => $self->uuid, creator     => $creator, $created ? ( created => $created ) : (), });
    
    $self->current_edit($changeset);
    $self->current_edit_records( [] );
    $self->dbh->begin_work;

}

sub _set_original_source_metadata_for_current_edit {
    my $self = shift;
    my ($changeset) = validate_pos( @_, { isa => 'Prophet::ChangeSet' } );

    $self->current_edit->original_source_uuid( $changeset->original_source_uuid );
    $self->current_edit->original_sequence_no( $changeset->original_sequence_no );
}

sub commit_edit {
    my $self     = shift;
    $self->current_edit->original_source_uuid( $self->uuid ) unless ( $self->current_edit->original_source_uuid );


    my $local_id = $self->_write_changeset_to_db($self->current_edit);
    # XXX TODO SET original_sequence_no
    $self->dbh->commit;
    $self->current_edit(undef);
}

sub _write_changeset_to_db {
    my $self = shift;
    my $changeset = shift;

    $self->dbh->do(
        "INSERT INTO changesets "
            . "(creator, created,"
            . "original_source_uuid, original_sequence_no, "
            . "is_nullification, is_resolution) "
            . "VALUES(?,?,?,?,?,?)", {},
        $changeset->creator, $changeset->created,

        $changeset->original_source_uuid,
        $changeset->original_sequence_no, $changeset->is_nullification,
        $changeset->is_resolution

    );

    my $local_id = $self->dbh->last_insert_id(undef, undef, 'changesets', 'sequence_no');

    $self->dbh->do("UPDATE changesets set original_sequence_no = sequence_no WHERE sequence_no = ?", {}, $local_id) unless ($changeset->original_sequence_no);

    for my $change (@{$changeset->changes}) {
        $self->_write_change_to_db($change, $local_id);
    }

    return $local_id;
}

sub _write_change_to_db {
    my $self = shift;
    my $change = shift;
    my $changeset_id = shift;

    $self->dbh->do(
        "INSERT INTO changes (record, changeset, change_type,
        record_type) VALUES (?,?,?,?)", {}, $change->record_uuid, $changeset_id,
        $change->change_type, $change->record_type
    );
    my $change_id = $self->dbh->last_insert_id(undef, undef, 'changes', 'id');
    for my $pc (@{$change->prop_changes}) {
        $self->_write_prop_change_to_db($change_id, $pc);
    }

}

sub _write_prop_change_to_db {
    my $self = shift;
    my $change = shift;
    my $pc = shift;

    $self->dbh->do("INSERT INTO prop_changes (change, name, old_value, new_value) VALUES (?,?,?,?)", {}, $change, $pc->name, $pc->old_value, $pc->new_value);

}

sub _after_record_changes {
    my $self = shift;
    my ($changeset) = validate_pos( @_, { isa => 'Prophet::ChangeSet' } );
    $self->current_edit->is_nullification( $changeset->is_nullification );
    $self->current_edit->is_resolution( $changeset->is_resolution );
}

sub create_record {
    my $self = shift;
    my %args = validate( @_, { uuid => 1, props => 1, type => 1 } );

    my $inside_edit = $self->current_edit ? 1 : 0;
    $self->begin_edit() unless ($inside_edit);
    $self->_write_record_to_db( type  => $args{'type'}, uuid  => $args{'uuid'}, props => $args{'props'});
    my $change = Prophet::Change->new( {   record_type => $args{'type'}, record_uuid => $args{'uuid'}, change_type => 'add_file' });
    $change->add_prop_change( name => $_, old  => undef, new  => $args{props}->{$_}) for (keys %{$args{props}});
    $self->current_edit->add_change( change => $change );
    $self->commit_edit unless ($inside_edit);
}

sub delete_record {
    my $self = shift;
    my %args = validate( @_, { uuid => 1, type => 1 } );

    my $inside_edit = $self->current_edit ? 1 : 0;
    $self->begin_edit() unless ($inside_edit);
    $self->_delete_record_from_db(uuid => $args{uuid});

    my $change = Prophet::Change->new( {   record_type => $args{'type'}, record_uuid => $args{'uuid'}, change_type => 'delete' });
    $self->current_edit->add_change( change => $change );

    $self->commit_edit() unless ($inside_edit);
    return 1;
}

sub set_record_props {
    my $self = shift;
    my %args = validate( @_, { uuid => 1, props => 1, type => 1 } );

    my $inside_edit = $self->current_edit ? 1 : 0;
    $self->begin_edit() unless ($inside_edit);
   
    # clear the cache  before computing the diffs. this is probably paranoid
    delete $PROP_CACHE->{$args{uuid}};
    
    my $old_props = $self->get_record_props( uuid => $args{'uuid'}, type => $args{'type'});
    my %new_props = %$old_props;

    for my $prop ( keys %{ $args{props} } ) {
        if ( !defined $args{props}->{$prop} ) {
            delete $new_props{$prop};
        } else {
            $new_props{$prop} = $args{props}->{$prop};
        }
    }

    $self->_write_record_to_db( type  => $args{'type'}, uuid  => $args{'uuid'}, props => \%new_props);

    # Clear the cache now that we've actually written out changed props
    delete $PROP_CACHE->{$args{uuid}};

    my $change = Prophet::Change->new( {   record_type => $args{'type'}, record_uuid => $args{'uuid'}, change_type => 'update_file' });
    $change->add_prop_change( name => $_, old  => $old_props->{$_}, new  => $args{props}->{$_}) for (keys %{$args{props}});
    $self->current_edit->add_change( change => $change );
    $self->commit_edit() unless ($inside_edit);

    return 1;
}

sub get_record_props {
    my $self = shift;
    my %args = ( uuid => undef, type => undef, @_ )
        ;    # validate is slooow validate( @_, { uuid => 1, type => 1 } );
    unless ( exists $PROP_CACHE->{ $args{uuid} } ) {
        my $sth = $self->dbh->prepare("SELECT prop, value from record_props WHERE uuid = ?");
        $sth->execute( $args{uuid} );
        my $items = $sth->fetchall_arrayref;
        $PROP_CACHE->{ $args{uuid} } = {map {@$_} @$items};
    }
    return $PROP_CACHE->{ $args{uuid} };
}

sub record_exists {
    my $self = shift;
    my %args = validate( @_, { uuid => 1, type => 1 } );
    return undef unless $args{'uuid'};

    my $sth = $self->dbh->prepare("SELECT luid from records WHERE type = ? AND uuid = ?");
    $sth->execute($args{type}, $args{uuid});
    return $sth->fetchrow_array;

}

=head2 list_records { type => $type }

Returns a reference to a list of record objects for all records of type $type.

Order is not guaranteed.

=cut

sub list_records {
    my $self = shift;
    my %args = validate( @_ => { type => 1, record_class => 1 } );
    my @data;
    my $sth = $self->dbh->prepare("SELECT records.uuid, records.luid, record_props.prop, record_props.value ".
        "FROM records, record_props ".
        "WHERE records.uuid = record_props.uuid AND records.type = ?");
    $sth->execute($args{type});

    my %found;

    for (@{$sth->fetchall_arrayref}) { 
        $found{$_->[0]}->{luid} = $_->[1];
        $found{$_->[0]}->{props}->{$_->[2]} = $_->[3];
    } 


    for my $uuid (keys %found) {
        my $record = $args{record_class}->new( { app_handle => $self->app_handle,  handle => $self, type => $args{type} } );
        $record->_instantiate_from_hash( uuid => $uuid, luid => $found{$uuid}->{luid});
        #$PROP_CACHE->{$uuid} = $found{$uuid}->{props};
        push @data, $record;    
    } 
    return \@data;
}

sub list_types {
    my $self = shift;

    my $sth = $self->dbh->prepare("SELECT DISTINCT type from records");
    $sth->execute();
    return [ map { $_->[0]} @{$sth->fetchall_arrayref}];
}

sub type_exists {
    my $self = shift;
    my %args = (type =>undef, @_);
    my $sth = $self->dbh->prepare("SELECT type from records WHERE type = ? LIMIT 1");
    $sth->execute($args{type});
    return $sth->fetchrow_array;

}

=head2 read_userdata_file

Returns the contents of the given file in this replica's userdata directory.
Returns C<undef> if the file does not exist.

=cut

sub read_userdata {
    my $self = shift;
    my %args = validate( @_, { path => 1 } );
    return $self->_fetch_userdata( $args{path} );
}

=head2 write_userdata_file

Writes the given string to the given file in this replica's userdata directory.

=cut

sub write_userdata {
    my $self = shift;
    my %args = validate( @_, { path => 1, content => 1 } );
    $self->_store_userdata(
        key   => $args{path},
        value => $args{content},
    );
}


=head1 Working with luids

=cut

sub find_or_create_luid {
    my $self = shift;
    my %args = (uuid => undef, type => undef, @_); # validate is slooow validate( @_, { uuid => 1, type => 1 } );
    return undef unless $args{'uuid'};

    my $sth = $self->dbh->prepare("SELECT luid from records WHERE uuid = ?");
    $sth->execute( $args{uuid});
    return $sth->fetchrow_array;
}

sub find_luid_by_uuid {
    my $self = shift;
    my %args = validate( @_, { uuid => 1 } );

    my $sth = $self->dbh->prepare("SELECT luid from records WHERE uuid = ?");
    $sth->execute( $args{uuid});
    return $sth->fetchrow_array;
}

sub find_uuid_by_luid {
    my $self = shift;
    my %args = validate( @_, { luid => 1 } );
    return undef unless $args{'luid'};

    my $sth = $self->dbh->prepare("SELECT uuid from records WHERE luid = ?");
    $sth->execute( $args{luid});
    return $sth->fetchrow_array;
}

sub _upgrade_replica_to_v2 {
    my $self = shift;

    $self->_do_db_upgrades(
        statements => [
            q{CREATE TABLE new_records (luid INTEGER PRIMARY KEY, uuid TEXT, type TEXT)},
            q{INSERT INTO new_records (uuid, type) SELECT uuid, type FROM records},
            q{DROP TABLE records},
            q{ALTER TABLE new_records RENAME TO records}
        ],
        version => 2
    );

}

sub _do_db_upgrades {
    my $self = shift;
    my %args = (
        statements => undef,
        version    => undef,
        @_
    );

    $self->dbh->begin_work;
    foreach my $s ( @{ $args{statements} } ) {
        $self->dbh->do($s) || warn $self->dbh->errstr;
    }
    $self->set_replica_version( $args{version} );

    $self->dbh->commit;

}


sub DEMOLISH {
    my $self = shift;
    $self->dbh->disconnect if ( $self->dbh );
}


__PACKAGE__->meta->make_immutable;
no Any::Moose;

1;
