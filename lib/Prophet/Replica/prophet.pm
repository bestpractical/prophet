package Prophet::Replica::prophet;
use Moose;
extends 'Prophet::Replica';
use Params::Validate qw(:all);
use LWP::Simple ();
use File::Spec  ();
use File::Path;
use Cwd ();
use Digest::SHA1 qw(sha1_hex);
use File::Find::Rule;
use Data::UUID;
use Prophet::Util;
use JSON;
use POSIX qw();
use Memoize;


has '+db_uuid' => (
    lazy    => 1,
    default => sub { shift->_read_file('database-uuid') },
);

has _uuid => ( is => 'rw', );

has replica_version => (
    is      => 'ro',
    writer  => '_set_replica_version',
    isa     => 'Int',
    lazy    => 1,
    default => sub { shift->_read_file('replica-version') || 0 }
);

has fs_root_parent => (
    is      => 'rw',
    lazy    => 1,
    default => sub {
        my $self = shift;
        return $self->url =~ m{^file://(.*)/.*?$} ? $1 : undef;
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

has current_edit => ( is => 'rw', );

has current_edit_records => (
    metaclass => 'Collection::Array',
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

=head2 replica_exists

Returns true if the replica already exists / has been initialized.
Returns false otherwise.

=cut

sub replica_exists {
    my $self = shift;
    return $self->replica_version ? 1 : 0;
}

=head2 set_replica_version

Sets the replica's version to the given integer.

=cut

sub set_replica_version {
    my $self    = shift;
    my $version = shift;

    $self->_set_replica_version($version);

    $self->_write_file(
        path    => 'replica-version',
        content => $version,
    );

    return $version;
}


sub store_local_metadata {
    my $self = shift;
    my $key = shift;
    my $value = shift;
    $self->_write_file(
        path    =>File::Spec->catfile( $self->local_metadata_dir,  $key),
        content => $value,
    );


}

sub fetch_local_metadata {
    my $self = shift;
    my $key = shift;
    $self->_read_file(File::Spec->catfile($self->local_metadata_dir, $key));

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

sub initialize {
    my $self = shift;
    my %args = validate(
        @_,
        {   db_uuid    => 0,
            resdb_uuid => 0,
        }
    );

    if ( !$self->fs_root_parent ) {

        if ( $self->can_write_changesets ) {
            die
                "We can only create local prophet replicas. It looks like you're trying to create "
                . $self->url;
        } else {
            die "Prophet couldn't find a replica at \""
                . $self->url
                . "\"\n\n"
                . "Please check the URL and try again.\n";

        }
    }

    return if $self->replica_exists;

    for (
        $self->record_dir,     $self->cas_root,
        $self->record_cas_dir, $self->changeset_cas_dir,
        $self->userdata_dir
        )
    {
        mkpath( [ File::Spec->catdir( $self->fs_root => $_ ) ] );
    }

    $self->set_db_uuid( $args{'db_uuid'} || Data::UUID->new->create_str );
    $self->set_latest_sequence_no("0");
    $self->set_replica_uuid( Data::UUID->new->create_str );

    $self->set_replica_version(1);

    $self->resolution_db_handle->initialize( db_uuid => $args{resdb_uuid} )
        if !$self->is_resdb;

    $self->after_initialize->($self);
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

Return the replica SVN repository's UUID

=cut

sub uuid {
    my $self = shift;
    $self->_uuid( $self->_read_file('replica-uuid') ) unless $self->_uuid;
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

before set_db_uuid => sub {
    my $self = shift;
    my $uuid = shift;
    $self->_write_file(
        path    => 'database-uuid',
        content => $uuid
    );
};

=head1 Internals of record handling

=cut

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
    my ($cas_key) = $self->_write_to_cas(
        data    => $args{props},
        cas_dir => $self->record_cas_dir
    );

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

sub _last_record_index_entry {
    my $self = shift;
    my %args = ( type => undef, uuid => undef, @_);

    my $idx_filename = File::Spec->catfile(
        $self->fs_root => $self->_record_index_filename( uuid => $args{uuid}, type => $args{type})
    );

    open( my $index, "<:bytes", $idx_filename) || return undef;
    seek($index, (0 - RECORD_INDEX_SIZE), 2) || return undef;
    my $record;
    read( $index, $record, RECORD_INDEX_SIZE) || return undef;
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

    my $index = $self->_read_file($idx_filename);
    return undef unless $index;

    # XXX TODO THIS CODE IS HACKY AND SHOULD BE SHOT;
    my $count = length($index) / RECORD_INDEX_SIZE;
    my @entries;
    for my $offset ( 0 .. ( $count - 1 ) ) {
        my ( $seq, $key ) = unpack( 'NH40',
            substr( $index, ($offset) * RECORD_INDEX_SIZE, RECORD_INDEX_SIZE )
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

memoize '_record_index_filename';
sub _record_index_filename {
    my $self = shift;
    my %args = validate( @_, { uuid => 1, type => 1 } );
    return File::Spec->catfile( $self->_record_type_dir( $args{'type'} ), $self->_hashed_dir_name( $args{uuid} ));
}

sub _hashed_dir_name {
    my $self = shift;
    my $hash = shift;

    return ( substr( $hash, 0, 1 ), substr( $hash, 1, 1 ), $hash );
}

sub _record_cas_filename {
    my $self = shift;
    my %args = ( type => undef, uuid => undef, @_) ;

    my ( $seq, $key ) = $self->_last_record_index_entry(
        type => $args{'type'},
        uuid => $args{'uuid'}
    );

    return undef unless ( $key and ( $key ne '0' x 40 ) );
    return File::Spec->catfile( $self->record_cas_dir, $self->_hashed_dir_name($key) );
}

sub _record_type_dir {
    my $self = shift;
    my $type = shift;
    return File::Spec->catdir( $self->record_dir, $type );
}

sub _write_changeset {
    my $self = shift;
    my %args = validate( @_,
        { index_handle => 1, changeset => { isa => 'Prophet::ChangeSet' } } );

    my $changeset = $args{'changeset'};
    my $fh        = $args{'index_handle'};

    my $hash_changeset = $changeset->as_hash;

# XXX TODO: we should not be calculating the changeset's sha1 with the 'replica_uuid' and 'sequence_no' inside it. that makes every replica have a different hash for what should be the samechangeset.

    # These ttwo things should never actually get stored
    my $seqno = delete $hash_changeset->{'sequence_no'};
    my $uuid  = delete $hash_changeset->{'replica_uuid'};

    my $cas_key = $self->_write_to_cas(
        data    => $hash_changeset,
        cas_dir => $self->changeset_cas_dir
    );

    my $packed_cas_key = pack( 'H40', $cas_key );

    my $changeset_index_line = pack( 'Na16Na20',
        $seqno,
        Data::UUID->new->from_string( $changeset->original_source_uuid ),
        $changeset->original_sequence_no,
        $packed_cas_key );
    print $fh $changeset_index_line || die $!;

}

use constant CHG_RECORD_SIZE => ( 4 + 16 + 4 + 20 );

sub _get_changeset_index_entry {
    my $self = shift;
    my %args = validate( @_, { sequence_no => 1, index_file => 1 } );

    my $chgidx = $args{index_file};
    my $rev    = $args{'sequence_no'};
    my $index_record
        = substr( $$chgidx, ( $rev - 1 ) * CHG_RECORD_SIZE, CHG_RECORD_SIZE );
    my ( $seq, $orig_uuid, $orig_seq, $key )
        = unpack( 'Na16NH40', $index_record );

    $self->log_debug( join( ",", ( $seq, $orig_uuid, $orig_seq, $key ) ) );
    $orig_uuid = Data::UUID->new->to_string($orig_uuid);
    $self->log_debug( "REV: $rev - seq $seq - originally $orig_seq from "
            . substr( $orig_uuid, 0, 6 )
            . " data key $key" );

    # XXX: deserialize the changeset content from the cas with $key
    my $casfile = File::Spec->catfile(
        $self->changeset_cas_dir => $self->_hashed_dir_name($key) );

    my $changeset = $self->_deserialize_changeset(
        content              => $self->_read_file($casfile),
        original_source_uuid => $orig_uuid,
        original_sequence_no => $orig_seq,
        sequence_no          => $seq
    );

    return $changeset;
}

=head2 traverse_changesets { after => SEQUENCE_NO, callback => sub { } } 

Walks through all changesets from $after to $until, calling $callback on each.

If no $until is specified, the latest changeset is assumed.

=cut

# each record is : local-replica-seq-no : original-uuid : original-seq-no : cas key
#                  4                    16              4                 20

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

    my $chgidx = $self->_read_changeset_index;
    $self->log_debug("Traversing changesets between $first_rev and $latest");
    for my $rev ( $first_rev .. $latest ) {
        $self->log_debug("Fetching changeset $rev");
        my $changeset = $self->_get_changeset_index_entry(
            sequence_no => $rev,
            index_file  => $chgidx
        );

        $args{callback}->($changeset);
    }
}

sub _read_changeset_index {
    my $self = shift;
    $self->log_debug("Reading changeset index file");
    my $chgidx = $self->_read_file( $self->changeset_index );
    return \$chgidx;
}

=head2 changesets_for_record { uuid => $uuid, type => $type }

Returns an ordered set of changeset objects for all changesets containing
changes to this object. 

Note that changesets may include changes to other records

=cut

sub changesets_for_record {
    my $self = shift;
    my %args = validate( @_, { uuid => 1, type => 1 } );

    my @record_index = $self->_read_record_index(
        type => $args{'type'},
        uuid => $args{'uuid'}
    );

    my $changeset_index = $self->_read_changeset_index();

    my @changesets;
    for my $item (@record_index) {
        my $sequence = $item->[0];
        push @changesets,
            $self->_get_changeset_index_entry(
            sequence_no => $sequence,
            index_file  => $changeset_index
            );
    }

    return @changesets;

}

sub _deserialize_changeset {
    my $self = shift;
    my %args = validate(
        @_,
        {   content              => 1,
            original_sequence_no => 1,
            original_source_uuid => 1,
            sequence_no          => 1
        }
    );

    require Prophet::ChangeSet;
    my $content_struct = from_json( $args{content}, { utf8 => 1 } );
    my $changeset = Prophet::ChangeSet->new_from_hashref($content_struct);

    $changeset->source_uuid( $self->uuid );
    $changeset->sequence_no( $args{'sequence_no'} );
    $changeset->original_source_uuid( $args{'original_source_uuid'} );
    $changeset->original_sequence_no( $args{'original_sequence_no'} );
    return $changeset;
}

sub _get_changeset_index_handle {
    my $self = shift;

    open(
        my $cs_file,
        ">>" . File::Spec->catfile( $self->fs_root => $self->changeset_index )
    ) || die $!;
    return $cs_file;
}

sub _write_to_cas {
    my $self = shift;
    my %args = validate( @_, { content_ref => 0, cas_dir => 1, data => 0 } );
    my $content;
    if ( $args{'content_ref'} ) {
        $content = ${ $args{'content_ref'} };
    } elsif ( $args{'data'} ) {
        $content = to_json( $args{'data'},
            { canonical => 1, pretty => 0, utf8 => 1 } );
    }
    my $fingerprint      = sha1_hex($content);
    my $content_filename = File::Spec->catfile(
        $args{'cas_dir'} => $self->_hashed_dir_name($fingerprint) );

    $self->_write_file( path => $content_filename, content => $content );
    return $fingerprint;
}

sub _write_file {
    my $self = shift;
    my %args = validate( @_, { path => 1, content => 1 } );

    my $file = File::Spec->catfile( $self->fs_root => $args{'path'} );
    my ( undef, $parent, $filename ) = File::Spec->splitpath($file);
    unless ( -d $parent ) {
        eval { mkpath( [$parent] ) };
        if ( my $msg = $@ ) {
            die "Failed to create directory " . $parent . " - $msg";
        }
    }

    open( my $fh, ">$file" ) || die $!;
    print $fh scalar( $args{'content'} )
        ; # can't do "||" as we die if we print 0" || die "Could not write to " . $args{'path'} . " " . $!;
    close $fh || die $!;
}

=head2 _file_exists PATH

Returns true if PATH is a file or directory in this replica's directory structure

=cut

sub _file_exists {
    my $self = shift;
    my ($file) = validate_pos( @_, 1 );

    if ( !$self->fs_root ) {

        # HTTP Replica
        return $self->_read_file($file) ? 1 : 0;
    }

    my $path = File::Spec->catfile( $self->fs_root, $file );
    if    ( -f $path ) { return 1 }
    elsif ( -d $path ) { return 2 }
    else               { return 0 }
}

sub read_file {
    my $self = shift;
    my ($file) = validate_pos( @_, 1 );
    if ( $self->fs_root ) {

        # make sure we don't try to read files outside the replica
        my $qualified_file = Cwd::fast_abs_path(
            File::Spec->catfile( $self->fs_root => $file ) );
        return undef
            if substr( $qualified_file, 0, length( $self->fs_root ) ) ne
                $self->fs_root;
    }
    return $self->_read_file($file);
}

sub _read_file {
    my $self = shift;
    my ($file) = validate_pos( @_, 1 );
    if ( $self->fs_root ) {
        return eval {
            local $SIG{__DIE__} = 'DEFAULT';
            Prophet::Util->slurp(
                File::Spec->catfile( $self->fs_root => $file ) );
        };
    } else {    # http replica
        return LWP::Simple::get( $self->url . "/" . $file );
    }

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
        unless ( $self->current_edit->original_sequence_no );
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
    my $handle    = $self->_get_changeset_index_handle;
    $self->_write_changeset( index_handle => $handle, changeset => $changeset );
    close($handle) || die "Failed to close changeset handle: " . $handle;
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
    my @record_uuids
        = map { my @path = split( qr'/', $_ ); pop @path }
        File::Find::Rule->file->maxdepth(3)->in(
        File::Spec->catdir(
            $self->fs_root => $self->_record_type_dir( $args{'type'} )
        )
        );
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

    return [ map { my @path = split( qr'/', $_ ); pop @path }
            File::Find::Rule->mindepth(1)->maxdepth(1)
            ->in( File::Spec->catdir( $self->fs_root => $self->record_dir ) ) ];

}

sub type_exists {
    my $self = shift;
    my %args = validate( @_, { type => 1 } );
    return $self->_file_exists( $self->_record_type_dir( $args{'type'} ) );
}

=head2 read_userdata_file

Returns the contents of the given file in this replica's userdata directory.
Returns C<undef> if the file does not exist.

=cut

sub read_userdata {
    my $self = shift;
    my %args = validate( @_, { path => 1 } );

    $self->_read_file(
        File::Spec->catfile( $self->userdata_dir, $args{path} ) );
}

=head2 write_userdata

Writes the given string to the given file in this replica's userdata directory.

=cut

sub write_userdata {
    my $self = shift;
    my %args = validate( @_, { path => 1, content => 1 } );

    $self->_write_file(
        path    => File::Spec->catfile( $self->userdata_dir, $args{path} ),
        content => $args{content},
    );
}

__PACKAGE__->meta->make_immutable();
no Moose;

1;
