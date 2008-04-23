use warnings;
use strict;

package Prophet::ReplicaExporter;
use base qw/Class::Accessor/;
use Params::Validate qw(:all);
use Path::Class;
use UNIVERSAL::require;

__PACKAGE__->mk_accessors(qw( source_replica target_path target_replica));

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

    $self->target_replica(
        Prophet::Replica->new(
            { url => "prophet:file://" . $self->target_path }
        )
    );
    $self->target_replica->initialize();
    $self->_init_export_metadata();
    $self->export_records( type => $_ )
        for ( @{ $self->source_replica->list_types } );
    $self->export_changesets();

    unless ($self->source_replica->is_resdb) {
    my $resolutions = Prophet::ReplicaExporter->new(
        {   target_path => dir($self->target_path, 'resolutions' ),
            source_replica => $self->source_replica->resolution_db_handle
        }
    );
    $resolutions->export();
    }
}

sub _init_export_metadata {
    my $self = shift;
    $self->target_replica->set_latest_sequence_no(
        $self->source_replica->latest_sequence_no );
    $self->target_replica->set_replica_uuid( $self->source_replica->uuid );

}

sub export_records {
    my $self = shift;
    my %args = validate( @_, { type => 1 } );

    my $collection = Prophet::Collection->new(
        handle => $self->source_replica,
        type   => $args{type}
    );
    $collection->matching( sub {1} );
    $self->target_replica->_write_record( record => $_ ) for @$collection;

}

sub export_changesets {
    my $self = shift;

    my $cs_file = $self->target_replica->_get_changeset_index_handle();
    foreach my $changeset (
        @{ $self->source_replica->fetch_changesets( after => 0 ) } )
    {
        $self->target_replica->_write_changeset(
            index_handle => $cs_file,
            changeset    => $changeset
        );

    }
    close($cs_file);
}

1;
