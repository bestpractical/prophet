package Prophet::Replica::Native;
use Moose;
extends 'Prophet::Replica';
use Params::Validate qw(:all);
use LWP::Simple ();
use Path::Class;
use Digest::SHA1 qw(sha1_hex);
use File::Find::Rule;
use JSON;

use Prophet::ChangeSet;
use Prophet::Conflict;

has _db_uuid => (
    is => 'rw',
);

has _uuid => (
    is => 'rw',
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

has target_replica => (
    is => 'rw',
);

has current_edit => (
    is => 'rw',
);

has '+resolution_db_handle' => (
    isa     => 'Prophet::Replica | Undef',
    lazy    => 1,
    default => sub {
        my $self = shift;
        return if $self->is_resdb || $self->is_state_handle;
        return Prophet::Replica->new({
            url      => "prophet:" . $self->url . '/resolutions',
            is_resdb => 1,
        })
    },
);

#has '+state_handle' => (
#    isa     => 'Prophet::Replica | Undef',
#    lazy    => 1,
#    default => sub {
#        return if $self->is_state_handle;
#        return Prophet::Replica->new({
#            url             => "prophet:" . $self->url,
#            is_state_handle => 1
#        });
#    },
#);

use constant scheme            => 'prophet';
use constant cas_root          => 'cas';
use constant record_cas_dir    => dir( __PACKAGE__->cas_root => 'records' );
use constant changeset_cas_dir => dir( __PACKAGE__->cas_root => 'changesets' );
use constant record_dir        => 'records';
use constant changeset_index   => 'changesets.idx';

=head2 BUILD

Open a connection to the SVN source identified by C<$self->url>.

=cut

sub BUILD {
    my $self = shift;
    $self->{url}
        =~ s/^prophet://;  # url-based constructor in ::replica should do better
    $self->{url} =~ s{/$}{};
    $self->_probe_or_create_db();
}

sub state_handle { return shift; }

sub _probe_or_create_db {
    my $self = shift;

    return if $self->_read_file('replica-version');

    if ( $self->fs_root_parent ) {

        # We have a filesystem based replica. we can perform a create
        $self->initialize();

    } else {
        die "We can only create file: based prophet replicas. It looks like you're trying to create " . $self->url;
    }

}

use constant can_read_records    => 1;
use constant can_read_changesets => 1;
sub can_write_changesets { return ( shift->fs_root ? 1 : 0 ) }
sub can_write_records    { return ( shift->fs_root ? 1 : 0 ) }

sub initialize {
    my $self = shift;
    my %args = validate( @_, { db_uuid => 0 } );
    dir( $self->fs_root, $_ )->mkpath
        for (
        $self->record_dir,     $self->cas_root,
        $self->record_cas_dir, $self->changeset_cas_dir
        );

    $self->set_db_uuid( $args{'db_uuid'} || Data::UUID->new->create_str );
    $self->set_latest_sequence_no("0");
    $self->set_replica_uuid( Data::UUID->new->create_str );
    $self->_write_file(
        path    => 'replica-version',
        content => '1'
    );
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

sub db_uuid {
    my $self = shift;
    $self->_db_uuid( $self->_read_file('database-uuid') )
        unless $self->_db_uuid;
    return $self->_db_uuid;
}

sub set_db_uuid {
    my $self = shift;
    my $uuid = shift;
    $self->_write_file(
        path    => 'database-uuid',
        content => $uuid
    );

}

=head1 Internals of record handling

=cut

sub _write_record {
    my $self = shift;
    my %args = validate( @_, { record => { isa => 'Prophet::Record' }, } );
    $self->_write_serialized_record(
        type  => $args{'record'}->type,
        uuid  => $args{'record'}->uuid,
        props => $args{'record'}->get_props
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
    $self->_write_record_index_entry(
        uuid    => $args{uuid},
        type    => $args{type},
        cas_key => $cas_key
    );
}

sub _write_record_index_entry {
    my $self         = shift;
    my %args         = validate( @_, { type => 1, uuid => 1, cas_key => 1 } );
    my $idx_filename = $self->_record_index_filename(
        uuid => $args{uuid},
        type => $args{type}
    );

    my $index_path = file( $self->fs_root, $idx_filename );
    $index_path->parent->mkpath;

    my $record_index = $index_path->openw;

    # XXX TODO: skip if the index already has this version of the record;
    # XXX TODO FETCH THAT
    my $record_last_changed_changeset = 1;
    my $index_row
        = pack( 'NH40', $record_last_changed_changeset, $args{cas_key} );
    print $record_index $index_row || die $!;
    close $record_index;
}

sub _delete_record_index {
    my $self         = shift;
    my %args         = validate( @_, { type => 1, uuid => 1 } );
    my $idx_filename = $self->_record_index_filename(
        uuid => $args{uuid},
        type => $args{type}
    );
    file( $self->fs_root => $idx_filename )->remove
        || die "Could not delete record $idx_filename: " . $!;
}
use constant RECORD_INDEX_SIZE => ( 4 + 20 );

sub _read_serialized_record {
    my $self         = shift;
    my %args         = validate( @_, { type => 1, uuid => 1 } );
    my $idx_filename = $self->_record_index_filename(
        uuid => $args{uuid},
        type => $args{type}
    );

    my $index = $self->_read_file($idx_filename);
    return undef unless $index;

    # XXX TODO THIS CODE IS FUCKING HACKY AND SHOULD BE SHOT;
    my $count = length($index) / RECORD_INDEX_SIZE;

    my ( $seq, $key ) = unpack( 'NH40',
        substr( $index, ( $count - 1 ) * RECORD_INDEX_SIZE, RECORD_INDEX_SIZE )
    );

    # XXX: deserialize the changeset content from the cas with $key
    my $casfile = file(
        $self->record_cas_dir,
        substr( $key, 0, 1 ),
        substr( $key, 1, 1 ), $key
    );

    # That's the props
    return from_json( $self->_read_file($casfile), { utf8 => 1} );
}

sub _record_index_filename {
    my $self = shift;
    my %args = validate( @_, { uuid => 1, type => 1 } );
    return file(
        $self->_record_type_root( $args{'type'} ),
        substr( $args{uuid}, 0, 1 ),
        substr( $args{uuid}, 1, 1 ),
        $args{uuid}
    );
}

sub _record_type_root {
    my $self = shift;
    my $type = shift;
    return dir( $self->record_dir, $type );
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

=head2 traverse_changesets { after => SEQUENCE_NO, callback => sub { } } 

Walks through all changesets after $after, calling $callback on each.


=cut

# each record is : local-replica-seq-no : original-uuid : original-seq-no : cas key
#                  4                    16              4                 20

use constant CHG_RECORD_SIZE => ( 4 + 16 + 4 + 20 );

sub traverse_changesets {
    my $self = shift;
    my %args = validate(
        @_,
        {   after    => 1,
            callback => 1,
        }
    );
    my $first_rev = ( $args{'after'} + 1 ) || 1;
    my $latest    = $self->latest_sequence_no();
    my $chgidx    = $self->_read_file( $self->changeset_index );

    $self->log("Traversing changesets between $first_rev and $latest");
    for my $rev ( $first_rev .. $latest ) {
        my $index_record = substr( $chgidx, ( $rev - 1 ) * CHG_RECORD_SIZE,
            CHG_RECORD_SIZE );
        my ( $seq, $orig_uuid, $orig_seq, $key )
            = unpack( 'Na16NH40', $index_record );

        $orig_uuid = Data::UUID->new->to_string($orig_uuid);
        $self->log( "REV: $rev - seq $seq - originally $orig_seq from "
                . substr( $orig_uuid, 0, 6 )
                . " data key $key" );

        # XXX: deserialize the changeset content from the cas with $key
        my $casfile = file(
            $self->changeset_cas_dir,
            substr( $key, 0, 1 ),
            substr( $key, 1, 1 ), $key
        );

        my $changeset = $self->_deserialize_changeset(
            content              => $self->_read_file($casfile),
            original_source_uuid => $orig_uuid,
            original_sequence_no => $orig_seq,
            sequence_no          => $seq
        );
        $args{callback}->($changeset);
    }
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
    my $content_struct = from_json( $args{content} , { utf8 => 1 });
    my $changeset      = Prophet::ChangeSet->new_from_hashref($content_struct);

    $changeset->source_uuid( $self->uuid );
    $changeset->sequence_no( $args{'sequence_no'} );
    $changeset->original_source_uuid( $args{'original_source_uuid'} );
    $changeset->original_sequence_no( $args{'original_sequence_no'} );
    return $changeset;
}

sub _get_changeset_index_handle {
    my $self = shift;

    open( my $cs_file, ">>" . file( $self->fs_root, $self->changeset_index ) )
        || die $!;
    return $cs_file;
}

sub _write_to_cas {
    my $self = shift;
    my %args = validate( @_,
        { content_ref => 0, cas_dir => 1, data => 0  } );
    my $content;
    if ( $args{'content_ref'} ) {
        $content = ${ $args{'content_ref'} };
    } elsif ( $args{'data'} ) {
        $content = to_json($args{'data'}, { canonical => 1, pretty=> 0, utf8=>1}  );
    }
    my $fingerprint = sha1_hex($content);
    my $content_filename = file(
        $args{'cas_dir'},
        substr( $fingerprint, 0, 1 ),
        substr( $fingerprint, 1, 1 ), $fingerprint
    );

    $self->_write_file( path => $content_filename, content => $content );
    return $fingerprint;
}

sub _write_file {
    my $self = shift;
    my %args = validate( @_, { path => 1, content => 1 } );

    my $file = file( $self->fs_root => $args{'path'} );
    my $parent = $file->parent;
    unless ( -d $parent ) {
        $parent->mkpath || die "Failed to create directory " . $file->parent;
    }

    my $fh = $file->openw;
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

    if ( $self->fs_root ) {
        my $path = file( $self->fs_root, $file );
        if    ( -f $path ) { return 1 }
        elsif ( -d $path ) { return 2 }
        else               { return 0 }
    } else {
        return $self->_read_file($file) ? 1 : 0;
    }
}

sub _read_file {
    my $self = shift;
    my ($file) = validate_pos( @_, 1 );
    if ( $self->fs_root ) {
        if ( $self->_file_exists($file) ) {
            return scalar file( $self->fs_root => $file )->slurp;
        } else {
            return undef;
        }
    } else {    # http replica
        return LWP::Simple::get( $self->url . "/" . $file );
    }
}

sub begin_edit {
    my $self = shift;
    $self->current_edit(
        Prophet::ChangeSet->new( { source_uuid => $self->uuid } ) );
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

    foreach my $name ( keys %{ $args{props} } ) {
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

# XXX TODO Write out an entry to the record's index file marking it as a special deleted uuid? - this has lots of ramifications for list, load, exists, create
    $self->_delete_record_index( uuid => $args{uuid}, type => $args{type} );

    my $change = Prophet::Change->new(
        {   record_type => $args{'type'},
            record_uuid => $args{'uuid'},
            change_type => 'delete'
        }
    );
    $self->current_edit->add_change( change => $change );

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
    foreach my $prop ( keys %{ $args{props} } ) {
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

    foreach my $name ( keys %{ $args{props} } ) {
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
    return $self->_file_exists(
        $self->_record_index_filename(
            type => $args{'type'},
            uuid => $args{'uuid'}
        )
    );

    # TODO, check that the index file doesn't have a 'deleted!' note
}

sub list_records {
    my $self = shift;
    my %args = validate( @_ => { type => 1 } );

    #return just the filenames, which, File::Find::Rule doesn't seem capable of
    return [
        map { my @path = split( qr'/', $_ ); pop @path }
            File::Find::Rule->file->maxdepth(3)->in(
            dir( $self->fs_root, $self->_record_type_root( $args{'type'} ) )
            )
    ];
}

sub list_types {
    my $self = shift;

    return [ map { my @path = split( qr'/', $_ ); pop @path }
            File::Find::Rule->mindepth(1)->maxdepth(1)
            ->in( dir( $self->fs_root, $self->record_dir ) ) ];

}

sub type_exists {
    my $self = shift;
    my %args = validate( @_, { type => 1 } );
    return $self->_file_exists( $self->_record_type_root( $args{'type'} ) );
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;
