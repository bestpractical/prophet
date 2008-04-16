use warnings;
use strict;

package Prophet::Replica::Native;
use base qw/Prophet::Replica/;
use Params::Validate qw(:all);
use LWP::Simple ();

use Path::Class;
use Digest::SHA1 qw(sha1 sha1_hex);
use YAML::Syck;
use Prophet::ChangeSet;
use Prophet::Conflict;

__PACKAGE__->mk_accessors(qw/url db_uuid _uuid/);
__PACKAGE__->mk_accessors(qw(fs_root target_replica cas_root record_cas_dir changeset_cas_dir record_dir));

use constant scheme => 'prophet';

=head2 setup

Open a connection to the SVN source identified by C<$self->url>.

=cut

sub setup {
    my $self = shift;

    $self->{url} =~ s/^prophet://;    # url-based constructor in ::replica should do better
    $self->{url} =~ s{/$}{};
    my ($db_uuid) = $self->url =~ m{^.*/(.*?)$};
    my ($fs_root) = $self->url =~ m{^file://(.*)$};
    $self->db_uuid($db_uuid);
    $self->fs_root($fs_root);
    unless ( $self->is_resdb ) {

      #        $self->resolution_db_handle( __PACKAGE__->new( { url => $self->{url}.'/resolutions', is_resdb => 1 } ) );
    }
}

sub initialize {
    my $self = shift;
    my %args = validate( @_, { db_uuid => 0 } );

    $self->cas_root( dir( 'cas' ) );
    $self->record_cas_dir( dir( $self->cas_root => 'records' ) );
    $self->changeset_cas_dir( dir( $self->cas_root => 'changesets' ) );
    $self->record_dir( dir( 'records' ) );

    _mkdir(dir($self->fs_root, $_)) for ('', $self->record_dir, $self->cas_root );
    $self->make_tiered_dirs( $self->record_cas_dir );
    $self->make_tiered_dirs( $self->changeset_cas_dir );

    $self->set_latest_sequence_no("1");
    $self->set_replica_uuid( Data::UUID->new->create_str );
    $self->_write_file( path => file( $self->fs_root, 'replica-version' ), content => '1' );
}

sub set_replica_uuid {
    my $self = shift;
    my $uuid = shift;
    $self->_write_file( path => file( $self->fs_root, 'replica-uuid' ), content => $uuid );

}

sub set_latest_sequence_no {
    my $self = shift;
    my $id   = shift;
    $self->_write_file( path => file( $self->fs_root, 'latest-sequence-no' ), content => scalar($id) );
}

=head2 uuid

Return the replica SVN repository's UUID

=cut

sub uuid {
    my $self = shift;

    $self->_uuid( $self->_read_file('/replica-uuid') ) unless $self->_uuid;
    return $self->_uuid;
}

sub _write_record {
    my $self = shift;
    my %args = validate( @_, { record => { isa => 'Prophet::Record' }, } );
    $self->_write_serialized_record( type => $args{'record'}->type, uuid => $args{'record'}->uuid, props => $args{'record'}->get_props);
}

sub _write_serialized_record {
    my $self = shift;
    my %args = validate( @_, { type => 1, uuid => 1, props =>1});

    my $record_root = dir( $self->_record_type_root($args{'type'}));
    $self->make_tiered_dirs($record_root) unless -d dir($self->fs_root, $record_root);

    my $content = YAML::Syck::Dump( $args{'props'});
    my ($cas_key) = $self->_write_to_cas(
        content_ref => \$content,
        cas_dir     => $self->record_cas_dir);
    my $idx_filename = $self->_record_index_filename(uuid =>$args{uuid}, type => $args{type});

    open( my $record_index, ">>", file($self->fs_root, $idx_filename) ) || die $!;

    # XXX TODO: skip if the index already has this version of the record;
    # XXX TODO FETCH THAT
    my $record_last_changed_changeset = 1;

    my $index_row = pack( 'NH40', $record_last_changed_changeset, $cas_key );
    print $record_index $index_row || die $!;
    close $record_index;
}


use constant RECORD_INDEX_SIZE => (4+ 20);
sub _read_serialized_record {
    my $self = shift;
    my %args = validate( @_, { type => 1, uuid => 1} ) ;
    my $idx_filename = $self->_record_index_filename(uuid =>$args{uuid}, type => $args{type});
    return undef unless -f $idx_filename;
    my $index = $self->_read_file($idx_filename);
    
    
    # XXX TODO THIS CODE IS FUCKING HACKY AND SHOULD BE SHOT; 
    my $count = length($index) / RECORD_INDEX_SIZE;

        my ( $seq,$key ) = unpack( 'NH40', substr( $index, ( $count - 1 ) * RECORD_INDEX_SIZE, RECORD_INDEX_SIZE ) );
        # XXX: deserialize the changeset content from the cas with $key
        my $casfile = file ($self->record_cas_dir, substr( $key, 0, 1 ), substr( $key, 1, 1 ) , $key);
        # That's the props
        return YAML::Syck::Load($self->_read_file($casfile));
}




sub _record_index_filename {
    my $self = shift;
    my %args = validate(@_,{ uuid =>1 ,type => 1});
    return file( $self->_record_type_root($args{'type'}) , substr( $args{uuid}, 0, 1 ), substr( $args{uuid}, 1, 1 ), $args{uuid});
}

sub _record_type_root {
    my $self = shift;
    my $type = shift; 
    return dir($self->record_dir, $type);
}


sub _write_changeset {
    my $self = shift;
    my %args = validate( @_, { index_handle => 1, changeset => { isa => 'Prophet::ChangeSet' } } );

    my $changeset = $args{'changeset'};
    my $fh        = $args{'index_handle'};

    my $hash_changeset = $changeset->as_hash;

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

=head2 traverse_changesets { after => SEQUENCE_NO, callback => sub { } } 

Walks through all changesets after $after, calling $callback on each.


=cut

# each record is : local-replica-seq-no : original-uuid : original-seq-no : cas key
#                       4                    16              4                 20

use constant CHG_RECORD_SIZE => ( 4 + 16 + 4 + 20 );

sub traverse_changesets {
    my $self = shift;
    my %args = validate(
        @_,
        {   after    => 1,
            callback => 1,
        }
    );

    my $first_rev = ( $args{'after'}+1) || 1;
    my $latest    = $self->latest_sequence_no();
    my $chgidx    = $self->_read_file('/changesets.idx');

    for my $rev ( $first_rev .. $latest ) {
        my ( $seq, $orig_uuid, $orig_seq, $key )
            = unpack( 'Na16NH40', substr( $chgidx, ( $rev - 1 ) * CHG_RECORD_SIZE, CHG_RECORD_SIZE ) );
        $orig_uuid = Data::UUID->new->to_string($orig_uuid);

        # XXX: deserialize the changeset content from the cas with $key
        my $casfile = file ($self->changeset_cas_dir, substr( $key, 0, 1 ), substr( $key, 1, 1 ) , $key);
        my $changeset = $self->_deserialize_changeset(
            content              => $self->_read_file($casfile),
            original_source_uuid => $orig_uuid,
            original_sequence_no => $orig_seq,
            sequence_no          => $seq
        );
        $args{callback}->($changeset);
    }
}




sub latest_sequence_no {
    my $self = shift;
    $self->_read_file('/latest-sequence-no');
}

sub _deserialize_changeset {
    my $self = shift;
    my %args = validate( @_, { content => 1, original_sequence_no => 1, original_source_uuid => 1, sequence_no => 1 } );
    my $content_struct = YAML::Syck::Load( $args{content} );
    my $changeset      = Prophet::ChangeSet->new_from_hashref($content_struct);
    # Don't need to do this, since we clobber them below
    #delete $hash_changeset->{'sequence_no'};
    #delete $hash_changeset->{'source_uuid'};
    $changeset->source_uuid( $self->uuid );
    $changeset->sequence_no( $args{'sequence_no'} );
    $changeset->original_source_uuid( $args{'original_source_uuid'} );
    $changeset->original_sequence_no( $args{'original_sequence_no'} );
    return $changeset;
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
    my $self = shift;
    my $base = shift;
    _mkdir( dir($self->fs_root, $base) );
    for my $a ( 0 .. 9, 'a' .. 'f' ) {
        _mkdir( dir( $self->fs_root, $base => $a ) );
        for my $b ( 0 .. 9, 'a' .. 'f' ) {
            _mkdir( dir($self->fs_root,  $base => $a => $b ) );
        }
    }

}

sub _write_to_cas {
    my $self        = shift;
    my %args        = validate( @_, { content_ref => 1, cas_dir => 1 } );
    my $content     = ${ $args{'content_ref'} };
    my $fingerprint = sha1_hex($content);
    my $content_filename
        = file( $self->fs_root, $args{'cas_dir'}, substr( $fingerprint, 0, 1 ), substr( $fingerprint, 1, 1 ), $fingerprint );

    $self->_write_file( path => $content_filename, content => $content );
    return $fingerprint;
}

sub _write_file {
    my $self = shift;
    my %args = validate( @_, { path => 1, content => 1 } );
    open( my $file, ">", $args{'path'} ) || die $!;
    print $file $args{'content'} || die "Could not write to " . $args{'path'} . " " . $!;
    close $file || die $!;
}

sub _file_exists {
    my $self = shift;
    my ($file) = validate_pos( @_, 1 );
    return -f file($self->fs_path, $file);
}
sub _read_file {
    my $self = shift;
    my ($file) = validate_pos( @_, 1 );
    LWP::Simple::get( $self->url . $file );
}

sub state_handle { return shift }  #XXX TODO better way to handle this?
sub record_changeset_integration {
    my ($self, $changeset) = validate_pos( @_, 1, { isa => 'Prophet::ChangeSet' } );

    $self->_set_original_source_metadata($changeset);
    return $self->SUPER::record_changeset_integration($changeset);
}
sub begin_edit {
}
sub commit_edit {
}
sub create_record {
    my $self = shift;
    my %args = validate( @_, { uuid => 1, props => 1, type => 1 } );
    $self->_write_serialized_record( type => $args{'type'}, uuid => $args{'uuid'}, props => $args{'props'});

}
sub delete_record {
    my $self = shift;
    my %args = validate( @_, { uuid => 1, type => 1 } );
    # Write out an entry to the record's index file marking it as a special deleted uuid?
}

sub set_record_props {
    my $self      = shift;
    my %args      = validate( @_, { uuid => 1, props => 1, type => 1 } );
    my %old_props = $self->get_record_props( uuid => $args{'uuid'}, type => $args{'type'} );
    foreach my $prop ( %{ $args{props} } ) {
        if ( !defined $args{props}->{$prop} ) {
            delete $old_props{$prop};
        } else {
            $old_props{$prop} = $args{props}->{$prop};
        }
    }
    $self->_write_serialized_record( type => $args{'type'}, uuid => $args{'uuid'}, props => \%old_props );
}
sub get_record_props {
    my $self = shift;
    my %args = validate( @_, { uuid => 1, type => 1 } );
    return $self->_read_serialized_record(uuid => $args{'uuid'}, type => $args{'type'});
}
sub record_exists {
    my $self = shift;
    my %args = validate( @_, { uuid => 1, type => 1} );
    return $self->_file_exists($self->_record_index_filename( type => $args{'type'}, uuid => $args{'uuid'}));
    # TODO, check that the index file doesn't have a 'deleted!' note
}
sub list_records {
    my $self = shift;
    my %args = validate( @_ => { type => 1 } );
    my @records = File::Find::Rule->file->in(dir($self->fs_root,$self->_record_type_root($args{'type'})))->maxdepth(3);
    die "have not yet dealt with what's in ".@records;
}
sub list_types {
    my $self = shift;
    my @types = File::Find::Rule->file->in(dir($self->fs_root, $self->record_dir))->maxdepth(1);
    die "have not post-processed ".@types;

}
sub type_exists {
    my $self = shift;
    my %args = validate( @_, { type => 1 } );
    return $self->_file_exists($self->_record_type_root( $args{'type'}));
}
1;
