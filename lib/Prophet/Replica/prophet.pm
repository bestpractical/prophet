package Prophet::Replica::prophet;
use Any::Moose;
extends 'Prophet::FilesystemReplica';

use Params::Validate qw(:all);
use LWP::UserAgent;
use LWP::ConnCache;
use File::Spec  ();
use File::Path;
use Cwd ();
use File::Find;
use Prophet::Util;
use POSIX qw();
use Memoize;
use Prophet::ContentAddressedStore;

use JSON;
use Digest::SHA qw(sha1_hex);

has '+db_uuid' => (
    lazy    => 1,
    default => sub { shift->_read_file('database-uuid') },
);

has _uuid => ( is => 'rw', );

has _replica_version => (
    is      => 'rw',
    isa     => 'Int',
    lazy    => 1,
    default => sub { shift->_read_file('replica-version') || 0 }
);

has fs_root_parent => (
    is      => 'rw',
    lazy    => 1,
    default => sub {
        my $self = shift;
        if ( $self->url =~ m{^file://(.*)} ) {
            my $path = $1;
            return File::Spec->catdir(
                ( File::Spec->splitpath($path) )[ 0, -2 ] );
        }
    },
);

has fs_root => (
    is      => 'rw',
    lazy    => 1,
    default => sub {
        my $self = shift;
        return $self->url =~ m{^file://(.*)$} ? $1 : undef;
    },
);

has record_cas => (
    is  => 'rw',
    isa => 'Prophet::ContentAddressedStore',
    lazy => 1,
    default => sub {
        my $self = shift;
        Prophet::ContentAddressedStore->new(
            { fs_root => $self->fs_root,
              root    => $self->record_cas_dir } );
    },
);

has changeset_cas => (
    is  => 'rw',
    isa => 'Prophet::ContentAddressedStore',
    lazy => 1,
    default => sub {
        my $self = shift;
        Prophet::ContentAddressedStore->new(
            { fs_root => $self->fs_root,
              root    => $self->changeset_cas_dir } );
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
            {   url        => "prophet:" . $self->url . '/resolutions',
                app_handle => $self->app_handle,
                is_resdb   => 1,
            }
        );
    },
);

has backend => (
	lazy => 1,
	is => 'rw',
	default => sub {
		my $self = shift;
		my $be;
		if ($self->url =~ /^http/i) {
			$be = 'Prophet::Replica::FS::Backend::LWP';
		} else {
			$be = 'Prophet::Replica::FS::Backend::File';
		};

		Prophet::App->require($be);
		return $be->new(url => $self->url, fs_root => $self->fs_root);
	}

);

use constant scheme   => 'prophet';
use constant cas_root => 'cas';
use constant record_cas_dir =>
    File::Spec->catdir( __PACKAGE__->cas_root => 'records' );
use constant changeset_cas_dir =>
    File::Spec->catdir( __PACKAGE__->cas_root => 'changesets' );
use constant record_dir      => 'records';
use constant userdata_dir    => 'userdata';
use constant changeset_index => 'changesets.idx';
use constant local_metadata_dir => 'local_metadata';

=head1 Replica Format

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

Inside the C<records> directory, you'll     warn "Got types ".join(',',@types);find directories named for each
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

=head2 BUILD

Open a connection to the prophet replica source identified by C<$self->url>.

=cut

sub BUILD {
    my $self = shift;
    my $args = shift;
    Carp::cluck() unless ( $args->{app_handle} );
    for ( $self->{url} ) {
        s/^prophet://;    # url-based constructor in ::replica should do better
        s{/$}{};
    }

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

    $self->_write_file(
        path    => 'replica-version',
        content => $version,
    );

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
sub can_write_changesets { return ( shift->fs_root ? 1 : 0 ) }
sub can_write_records    { return ( shift->fs_root ? 1 : 0 ) }


sub _on_initialize_create_paths {
		my $self = shift;
		return ( $self->record_dir, $self->cas_root, $self->record_cas_dir,
			$self->changeset_cas_dir, $self->userdata_dir );

}

sub initialize_backend {
    my $self = shift;
    my %args = validate(
        @_,
        {   db_uuid    => 0,
            resdb_uuid => 0,
        }
    );

    $self->set_db_uuid( $args{'db_uuid'} || $self->uuid_generator->create_str );
    $self->set_latest_sequence_no("0");
    $self->set_replica_uuid( $self->uuid_generator->create_str );

    $self->set_replica_version(1);

    $self->resolution_db_handle->initialize( db_uuid => $args{resdb_uuid} )
        if !$self->is_resdb;
}

sub latest_sequence_no {
    my $self = shift;
    $self->_read_file('latest-sequence-no');
}

sub set_latest_sequence_no {
    my $self = shift;
    my $id   = shift;
    $self->_write_file(
        path    => 'latest-sequence-no',
        content => scalar($id)
    );
}

sub _increment_sequence_no {
    my $self = shift;
    my $seq  = $self->latest_sequence_no + 1;
    $self->set_latest_sequence_no($seq);
    return $seq;
}

=head2 uuid

Return the replica's UUID

=cut

sub uuid {
    my $self = shift;
    $self->_uuid( $self->_read_file('replica-uuid') ) unless $self->_uuid;
#    die $@ if $@;
    return $self->_uuid;
}

sub set_replica_uuid {
    my $self = shift;
    my $uuid = shift;
    $self->_write_file(
        path    => 'replica-uuid',
        content => $uuid
    );

}

sub set_db_uuid {
    my $self = shift;
    my $uuid = shift;
    $self->_write_file(
        path    => 'database-uuid',
        content => $uuid
    );
    $self->SUPER::set_db_uuid($uuid);
}

=head1 Internals of record handling

=cut


# Working with records {

sub _write_record {
    my $self   = shift;
    my %args   = validate( @_, { record => { isa => 'Prophet::Record' }, } );
    my $record = $args{'record'};

    $self->_write_serialized_record(
        type  => $record->type,
        uuid  => $record->uuid,
        props => $record->get_props,
    );
}
sub _write_serialized_record {
    my $self = shift;
    my %args = validate( @_, { type => 1, uuid => 1, props => 1 } );

    for ( keys %{ $args{'props'} } ) {
        delete $args{'props'}->{$_}
            if ( !defined $args{'props'}->{$_} || $args{'props'}->{$_} eq '' );
    }
    my $cas_key = $self->record_cas->write( $args{props} );

    my $record = {
        uuid    => $args{uuid},
        type    => $args{type},
        cas_key => $cas_key
    };

    $self->_prepare_record_index_update(
        uuid    => $args{uuid},
        type    => $args{type},
        cas_key => $cas_key
    );
}

sub _prepare_record_index_update {
    my $self   = shift;
    my %record = (@_);

    # If we're inside an edit, we can record the changeset info into the index
    if ( $self->current_edit ) {
        push @{ $self->current_edit_records }, \%record;

    } else {

        # If we're not inside an edit, we're likely exporting the replica
        # TODO: the replica exporter code should probably be retooled
        $self->_write_record_index_entry(%record);
    }

}

use constant RECORD_INDEX_SIZE => ( 4 + 20 );

sub _write_record_index_entry {
    my $self = shift;
    my %args = validate( @_,
        { type => 1, uuid => 1, cas_key => 1, changeset_id => 0 } );
    my $idx_filename = $self->_record_index_filename(
        uuid => $args{uuid},
        type => $args{type}
    );

    my $index_path = File::Spec->catfile( $self->fs_root, $idx_filename );
    my ( undef, $parent, $filename ) = File::Spec->splitpath($index_path);
    mkpath( [$parent] );

    open( my $record_index, ">>" . $index_path );

    # XXX TODO: skip if the index already has this version of the record;
    # XXX TODO FETCH THAT
    my $record_last_changed_changeset = $args{'changeset_id'} || 0;
    my $index_row
        = pack( 'NH40', $record_last_changed_changeset, $args{cas_key} );
    print $record_index $index_row || die $!;
    close $record_index;
}

sub _read_file_range {
    my $self = shift;
    my %args = validate( @_, { path => 1, position => 1, length => 1 } );

	return $self->backend->read_file_range(%args);

}

sub _last_record_index_entry {
    my $self = shift;
    my %args = ( type => undef, uuid => undef, @_);

    my $idx_filename;
    my $record = $self->_read_file_range(
        path => $self->_record_index_filename( uuid => $args{uuid}, type => $args{type}),
        position => (0 - RECORD_INDEX_SIZE), 
        length => RECORD_INDEX_SIZE ) || return undef;

    my ( $seq, $key ) = unpack( "NH40", $record ) ;
    return ( $seq, $key );
}

sub _read_record_index {
    my $self = shift;
    my %args = validate( @_, { type => 1, uuid => 1 } );

    my $idx_filename = $self->_record_index_filename(
        uuid => $args{uuid},
        type => $args{type}
    );

    my $index = $self->backend->read_file($idx_filename);
    return undef unless $index;

    my $count = length($index) / RECORD_INDEX_SIZE;
    my @entries;
    for my $record ( 1 .. $count ) {
        my ( $seq, $key ) = unpack( 'NH40',
            substr( $index, ($record - 1) * RECORD_INDEX_SIZE, RECORD_INDEX_SIZE )
        );
        push @entries, [ $seq => $key ];
    }
    return @entries;
}

sub _delete_record_index {
    my $self         = shift;
    my %args         = validate( @_, { type => 1, uuid => 1 } );
    my $idx_filename = $self->_record_index_filename(
        uuid => $args{uuid},
        type => $args{type}
    );
    unlink File::Spec->catfile( $self->fs_root => $idx_filename )
        || die "Could not delete record $idx_filename: " . $!;
}

sub _read_serialized_record {
    my $self = shift;
    my %args = validate( @_, { type => 1, uuid => 1 } );

    my $casfile = $self->_record_cas_filename(
        type => $args{'type'},
        uuid => $args{'uuid'}
    );

    return undef unless $casfile;
    return from_json( $self->_read_file($casfile), { utf8 => 1 } );
}

# XXX TODO: memoize doesn't work on win:
# t\resty-server will issue the following error:
# Anonymous function called in forbidden list context; faulting
memoize '_record_index_filename' unless $^O =~ /MSWin/;


sub _record_index_filename {
    my $self = shift;
    my %args = validate( @_, { uuid => 1, type => 1 } );
    return File::Spec->catfile( $self->_record_type_dir( $args{'type'} ), Prophet::Util::hashed_dir_name( $args{uuid} ));
}

sub _record_cas_filename {
    my $self = shift;
    my %args = ( type => undef, uuid => undef, @_) ;

    my ( $seq, $key ) = $self->_last_record_index_entry(
        type => $args{'type'},
        uuid => $args{'uuid'}
    );

    return undef unless ( $key and ( $key ne '0' x 40 ) );
    return $self->record_cas->filename($key)
}

sub _record_type_dir {
    my $self = shift;
    my $type = shift;
    return File::Spec->catdir( $self->record_dir, $type );
}


# }


=head2 changesets_for_record { uuid => $uuid, type => $type, limit => $int }

Returns an ordered set of changeset objects for all changesets containing
changes to this object. 

Note that changesets may include changes to other records

If "limit" is specified, only returns that many changesets (starting from record creation).

=cut

sub changesets_for_record {
    my $self = shift;
    my %args = validate( @_, { uuid => 1, type => 1, limit => 0 } );

    my @record_index = $self->_read_record_index(
        type => $args{'type'},
        uuid => $args{'uuid'}
    );

    my $changeset_index = $self->read_changeset_index();

    my @changesets;
    for my $item (@record_index) {
        my $sequence = $item->[0];
        push @changesets,
            $self->_get_changeset_via_index(
            sequence_no => $sequence,
            index_file  => $changeset_index
            );
        last if (defined $args{limit} && --$args{limit});
    }

    return @changesets;

}




sub begin_edit {
    my $self = shift;
    my %args = validate(
        @_,
        {   source => 0,    # the changeset that we're replaying, if applicable
        }
    );

    my $source = $args{source};

    my $creator = $source ? $source->creator : $self->changeset_creator;
    my $created = $source && $source->created;

    require Prophet::ChangeSet;
    my $changeset = Prophet::ChangeSet->new(
        {   source_uuid => $self->uuid,
            creator     => $creator,
            $created ? ( created => $created ) : (),
        }
    );
    $self->current_edit($changeset);
    $self->current_edit_records( [] );

}

sub _set_original_source_metadata_for_current_edit {
    my $self = shift;
    my ($changeset) = validate_pos( @_, { isa => 'Prophet::ChangeSet' } );

    $self->current_edit->original_source_uuid(
        $changeset->original_source_uuid );
    $self->current_edit->original_sequence_no(
        $changeset->original_sequence_no );
}

sub commit_edit {
    my $self     = shift;
    my $sequence = $self->_increment_sequence_no;
    $self->current_edit->original_sequence_no($sequence)
        unless ( defined $self->current_edit->original_sequence_no );
    $self->current_edit->original_source_uuid( $self->uuid )
        unless ( $self->current_edit->original_source_uuid );
    $self->current_edit->sequence_no($sequence);
    for my $record ( @{ $self->current_edit_records } ) {
        $self->_write_record_index_entry( changeset_id => $sequence, %$record );
    }
    $self->_write_changeset_to_index( $self->current_edit );
}

sub _write_changeset_to_index {
    my $self      = shift;
    my $changeset = shift;
    $self->_write_changeset( changeset => $changeset );
    $self->current_edit(undef);
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

    $self->_write_serialized_record(
        type  => $args{'type'},
        uuid  => $args{'uuid'},
        props => $args{'props'}
    );

    my $change = Prophet::Change->new(
        {   record_type => $args{'type'},
            record_uuid => $args{'uuid'},
            change_type => 'add_file'
        }
    );

    for my $name ( keys %{ $args{props} } ) {
        $change->add_prop_change(
            name => $name,
            old  => undef,
            new  => $args{props}->{$name}
        );
    }

    $self->current_edit->add_change( change => $change );

    $self->commit_edit unless ($inside_edit);
}

sub delete_record {
    my $self = shift;
    my %args = validate( @_, { uuid => 1, type => 1 } );

    my $inside_edit = $self->current_edit ? 1 : 0;
    $self->begin_edit() unless ($inside_edit);

    my $change = Prophet::Change->new(
        {   record_type => $args{'type'},
            record_uuid => $args{'uuid'},
            change_type => 'delete'
        }
    );
    $self->current_edit->add_change( change => $change );

    $self->_prepare_record_index_update(
        uuid    => $args{uuid},
        type    => $args{type},
        cas_key => '0' x 40
    );

    $self->commit_edit() unless ($inside_edit);
    return 1;
}

sub set_record_props {
    my $self = shift;
    my %args = validate( @_, { uuid => 1, props => 1, type => 1 } );

    my $inside_edit = $self->current_edit ? 1 : 0;
    $self->begin_edit() unless ($inside_edit);

    my $old_props = $self->get_record_props(
        uuid => $args{'uuid'},
        type => $args{'type'}
    );
    my %new_props = %$old_props;
    for my $prop ( keys %{ $args{props} } ) {
        if ( !defined $args{props}->{$prop} ) {
            delete $new_props{$prop};
        } else {
            $new_props{$prop} = $args{props}->{$prop};
        }
    }
    $self->_write_serialized_record(
        type  => $args{'type'},
        uuid  => $args{'uuid'},
        props => \%new_props
    );

    my $change = Prophet::Change->new(
        {   record_type => $args{'type'},
            record_uuid => $args{'uuid'},
            change_type => 'update_file'
        }
    );

    for my $name ( keys %{ $args{props} } ) {
        $change->add_prop_change(
            name => $name,
            old  => $old_props->{$name},
            new  => $args{props}->{$name}
        );
    }
    $self->current_edit->add_change( change => $change );

    $self->commit_edit() unless ($inside_edit);
    return 1;
}

sub get_record_props {
    my $self = shift;
    my %args = validate( @_, { uuid => 1, type => 1 } );
    return $self->_read_serialized_record(
        uuid => $args{'uuid'},
        type => $args{'type'}
    );
}

sub record_exists {
    my $self = shift;
    my %args = validate( @_, { uuid => 1, type => 1 } );
    return undef unless $args{'uuid'};
    return $self->_record_cas_filename(
        type => $args{'type'},
        uuid => $args{'uuid'}
    ) ? 1 : 0;

}

sub list_records {
    my $self = shift;
    my %args = validate( @_ => { type => 1, record_class => 1 } );

    return [] unless $self->type_exists( type => $args{type} );
    #return just the filenames, which, File::Find::Rule doesn't seem capable of
    my @record_uuids;
        find sub { return unless -f $_; push @record_uuids, $_ },
        File::Spec->catdir(
            $self->fs_root => $self->_record_type_dir( $args{'type'} ));

    return [
        map { 
            my $record = $args{record_class}->new( { app_handle => $self->app_handle,  handle => $self, type => $args{type} } );
            $record->_instantiate_from_hash( uuid => $_);
            $record;
        }
        grep {
            $self->_record_cas_filename( type => $args{'type'}, uuid => $_ )
            } @record_uuids
    ];
    
        
        
}

sub list_types {
    my $self = shift;
    opendir( my $dh, File::Spec->catdir( $self->fs_root => $self->record_dir ) )
        || die "can't open type directory $!";
    my @types = grep {$_ !~ /^\./ } readdir($dh);
    closedir $dh;
    return \@types;
}

sub type_exists {
    my $self = shift;
    my %args = validate( @_, { type => 1 } );
    return $self->_file_exists( $self->_record_type_dir( $args{'type'} ) );
}


__PACKAGE__->meta->make_immutable();
no Any::Moose;

1;
