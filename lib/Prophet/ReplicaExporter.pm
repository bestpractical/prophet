use warnings;
use strict;

package Prophet::ReplicaExporter;
use base qw/Class::Accessor/;
use Params::Validate qw(:all);
use Path::Class;
use Digest::SHA1 qw(sha1 sha1_hex);
use YAML::Syck;
use UNIVERSAL::require;

__PACKAGE__->mk_accessors(
    qw( source_replica target_path    fs_root cas_root record_cas_dir changeset_cas_dir record_dir));

=head1 NAME

Prophet::ReplicaExporter

=head1 DESCRIPTION
                        
A utility class which exports a replica to a serialized on-disk format


=cut

=head1 METHODS

=head2 new

Instantiates a new replica exporter object

=cut

=head2 export

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

sub export {
    my $self = shift;
    
    $self->_initialize_replica( db_uuid => $self->source_replica->db_uuid );
    $self->_init_export_metadata();
    $self->export_records( type => $_ ) for ( @{ $self->source_replica->list_types } );
    $self->export_changesets();

    #$self->export_resolutions( path => dir( $fs_root, 'resolutions'), resdb_handle => $args{'resdb_handle'} );

}

sub export_resolutions {
    my $self    = shift;
    my $replica = Prophet::Replica->new();

    # ...
}

sub _initialize_replica {
    my $self = shift;
    my %args = validate(@_, { db_uuid => 0});

    $self->fs_root( dir( $self->target_path, $args{'db_uuid'} || Data::UUID->new->create_str()  ));
    $self->cas_root( dir( $self->fs_root => 'cas' ) );
    $self->record_cas_dir( dir( $self->cas_root => 'records' ) );
    $self->changeset_cas_dir( dir( $self->cas_root => 'changesets' ) );
    $self->record_dir( dir( $self->fs_root => 'records' ) );

    _mkdir($_) for ( $self->target_path, $self->fs_root, $self->record_dir, $self->cas_root );
    make_tiered_dirs( $self->record_cas_dir );
    make_tiered_dirs( $self->changeset_cas_dir );

    $self->_set_most_recent_changeset_no("1");
    $self->_set_replica_uuid(Data::UUID->new->create_str);
    $self->_output_oneliner_file( path => file( $self->fs_root, 'replica-version' ), content => '1' );
}

sub _init_export_metadata {
    my $self = shift;
    $self->_set_most_recent_changeset_no($self->source_replica->most_recent_changeset);
    $self->_set_replica_uuid( $self->source_replica->uuid);

}

sub _set_replica_uuid {
    my $self  = shift;
    my $uuid = shift;
    $self->_output_oneliner_file( path    => file( $self->fs_root, 'replica-uuid' ), content => $uuid);

}

sub _set_most_recent_changeset_no {
    my $self = shift;
    my $id = shift;
    $self->_output_oneliner_file( path    => file( $self->fs_root, 'latest-sequence-no' ), content => scalar($id));
}

sub export_records {
    my $self = shift;
    my %args = validate( @_, { type => 1 } );

    make_tiered_dirs( dir( $self->fs_root => 'records' => $args{'type'} ) );

    my $collection = Prophet::Collection->new(
        handle => $self->source_replica,
        type   => $args{type}
    );
    $collection->matching( sub {1} );
    $self->_write_record(
        record     => $_
    ) for @$collection;

}

sub _write_record {
    my $self = shift;
    my %args = validate(
        @_,
        {   record     => { isa => 'Prophet::Record' },
        }
    );

    my $record_dir = dir( $self->fs_root, 'records', $args{'record'}->type );
    my $content = YAML::Syck::Dump( $args{'record'}->get_props );
    my ($cas_key) = $self->_write_to_cas(
        content_ref => \$content,
        cas_dir     => $self->record_cas_dir
    );

    my $idx_filename = file( $record_dir,
        substr( $args{record}->uuid, 0, 1 ),
        substr( $args{record}->uuid, 1, 1 ),
        $args{record}->uuid
    );

    open( my $record_index, ">>", $idx_filename ) || die $!;

    # XXX TODO: skip if the index already has this version of the record;
    # XXX TODO FETCH THAT
    my $record_last_changed_changeset = 1;

    my $index_row = pack( 'NH40', $record_last_changed_changeset, $cas_key );
    print $record_index $index_row || die $!;
    close $record_index;
}

sub export_changesets {
    my $self = shift;

    open( my $cs_file, ">" . file( $self->fs_root, 'changesets.idx' ) ) || die $!;

    foreach my $changeset ( @{ $self->source_replica->fetch_changesets( after => 0 ) } ) {
        $self->_write_changeset( index_handle => $cs_file, changeset => $changeset );

    }
    close($cs_file);
}

sub _write_changeset {
    my $self = shift;
    my %args = validate( @_, { index_handle => 1, changeset => { isa => 'Prophet::ChangeSet' } } );

    my $changeset = $args{'changeset'};
    my $fh        = $args{'index_handle'};

    my $hash_changeset = $changeset->as_hash;
    delete $hash_changeset->{'sequence_no'};
    delete $hash_changeset->{'source_uuid'};

    my $content = YAML::Syck::Dump($hash_changeset);
    my $cas_key = $self->_write_to_cas( content_ref => \$content, cas_dir => $self->changeset_cas_dir );

    # XXX TODO we should only actually be encoding the sha1 of content once
    # and then converting. this is wasteful

    my $packed_cas_key = sha1($content);

    my $changeset_index_line = pack( 'Na16Na20',
        $changeset->sequence_no,
        Data::UUID->new->from_string( $changeset->original_source_uuid ),
        $changeset->original_sequence_no,
        $packed_cas_key );
    print $fh $changeset_index_line || die $!;

}

sub _mkdir {
    my $path = shift;
    unless ( -d $path ) {
        mkdir($path) || die $@;
    }
    unless ( -w $path ) {
        die "$path not writable";
    }

}

sub make_tiered_dirs {
    my $base = shift;
    _mkdir( dir($base) );
    for my $a ( 0 .. 9, 'a' .. 'f' ) {
        _mkdir( dir( $base => $a ) );
        for my $b ( 0 .. 9, 'a' .. 'f' ) {
            _mkdir( dir( $base => $a => $b ) );
        }
    }

}

sub _write_to_cas {
    my $self        = shift;
    my %args        = validate( @_, { content_ref => 1, cas_dir => 1 } );
    my $content     = ${ $args{'content_ref'} };
    my $fingerprint = sha1_hex($content);
    my $content_filename
        = file( $args{'cas_dir'}, substr( $fingerprint, 0, 1 ), substr( $fingerprint, 1, 1 ), $fingerprint );
    open( my $output, ">", $content_filename ) || die "Could not open $content_filename";
    print $output $content || die $!;
    close $output;
    return $fingerprint;
}

sub _output_oneliner_file {
    my $self = shift;
    my %args = validate( @_, { path => 1, content => 1 } );

    open( my $file, ">", $args{'path'} ) || die $!;
    print $file $args{'content'} || die "Could not write to ".$args{'path'} . " " . $!;
    close $file || die $!;
}

1;
