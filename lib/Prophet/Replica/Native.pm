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
__PACKAGE__->mk_accessors( qw(fs_root target_replica cas_root record_cas_dir changeset_cas_dir record_dir));

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
    my %args = validate(@_, { db_uuid => 0});

    $self->cas_root( dir( $self->fs_root => 'cas' ) );
    $self->record_cas_dir( dir( $self->cas_root => 'records' ) );
    $self->changeset_cas_dir( dir( $self->cas_root => 'changesets' ) );
    $self->record_dir( dir( $self->fs_root => 'records' ) );

    _mkdir($_) for (  $self->fs_root, $self->record_dir, $self->cas_root );
    make_tiered_dirs( $self->record_cas_dir );
    make_tiered_dirs( $self->changeset_cas_dir );

    $self->set_most_recent_changeset_no("1");
    $self->set_replica_uuid(Data::UUID->new->create_str);
    $self->_output_oneliner_file( path => file( $self->fs_root, 'replica-version' ), content => '1' );
}

sub set_replica_uuid {
    my $self  = shift;
    my $uuid = shift;
    $self->_output_oneliner_file( path    => file( $self->fs_root, 'replica-uuid' ), content => $uuid);

}

sub set_most_recent_changeset_no {
    my $self = shift;
    my $id = shift;
    $self->_output_oneliner_file( path    => file( $self->fs_root, 'latest-sequence-no' ), content => scalar($id));
}

=head2 uuid

Return the replica SVN repository's UUID

=cut

sub uuid {
    my $self = shift;

    $self->_uuid( LWP::Simple::get( $self->url . '/replica-uuid' ) ) unless $self->_uuid;
    return $self->_uuid;
}

sub _write_record {
    my $self = shift;
    my %args = validate(
        @_,
        {   record     => { isa => 'Prophet::Record' },
        }
    );

    my $record_dir = dir( $self->fs_root, 'records', $args{'record'}->type );
    make_tiered_dirs($record_dir) unless -d $record_dir;
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

=head2 fetch_changesets { after => SEQUENCE_NO } 

Fetch all changesets from the source. 

Returns a reference to an array of L<Prophet::ChangeSet/> objects.


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

    my $first_rev = ( $args{'after'} + 1 ) || 1;
    my $latest    = $self->most_recent_changeset();
    my $chgidx    = LWP::Simple::get( $self->url . '/changesets.idx' );

    for my $rev ( $first_rev .. $latest ) {
        my ( $seq, $orig_uuid, $orig_seq, $key )
            = unpack( 'Na16NH40', substr( $chgidx, ( $rev - 1 ) * CHG_RECORD_SIZE, CHG_RECORD_SIZE ) );
        $orig_uuid = Data::UUID->new->to_string($orig_uuid);

        # XXX: deserialize the changeset content from the cas with $key
        my $casfile = $self->url . '/cas/changesets/' . substr( $key, 0, 1 ) . '/' . substr( $key, 1, 1 ) . '/' . $key;
        my $changeset = $self->_deserialize_changeset(
            content              => LWP::Simple::get($casfile),
            original_source_uuid => $orig_uuid,
            original_sequence_no => $orig_seq,
            sequence_no          => $seq
        );
        $args{callback}->($changeset);
    }
}

sub most_recent_changeset {
    my $self = shift;
    return LWP::Simple::get( $self->url . '/latest-sequence-no' );
}

sub _deserialize_changeset {
    my $self = shift;

    my %args = validate( @_, { content => 1, original_sequence_no => 1, original_source_uuid => 1, sequence_no => 1 } );
    my $content_struct = YAML::Syck::Load( $args{content} );
    my $changeset      = Prophet::ChangeSet->new_from_hashref($content_struct);
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
