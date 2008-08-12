package Prophet::Replica::SVN;
use Moose;
extends 'Prophet::Replica';
use Params::Validate qw(:all);

# require rather than use to make them late-binding
use Prophet::ChangeSet;
use Prophet::Conflict;

has ra => (
    is      => 'rw',
    isa     => 'SVN::Ra',
    lazy    => 1,
    default => sub {
        my $self = shift;
        require Prophet::Replica::SVN::Util;
        my ( $baton, $ref ) = SVN::Core::auth_open_helper( Prophet::Replica::SVN::Util->get_auth_providers );
        my $config = Prophet::Replica::SVN::Util->svnconfig;
        return SVN::Ra->new(url => $self->url, config => $config, auth => $baton, pool => $self->_pool);
    },
);

has fs_root => (
    is => 'rw',
);

has repo_handle => (
    is => 'rw',
);

has current_edit => (
    is => 'rw',
);

has _pool => (
    is => 'rw',
);

use constant scheme => 'svn';


=head2 setup

Open a connection to the SVN source identified by C<$self->url>.

=cut

sub setup {
    my $self = shift;
   require SVN::Core; require SVN::Ra; require SVN::Delta; require SVN::Repos; require SVN::Fs;
    $self->_pool(SVN::Pool->new);
    if ( $self->url =~ /^file:\/\/(.*)$/ ) {
        $self->_setup_repo_connection( repository => $1 );
        #$self->state_handle( $self->prophet_handle ); XXX DO THIS RIGHT
    }

    if ( $self->is_resdb ) {

        # XXX: should probably just point to self
        return;
    }

    my $res_url = "svn:" . $self->url;
    $res_url =~ s/(\_res|)$/_res/;
    $self->resolution_db_handle( __PACKAGE__->new( { url => $res_url, is_resdb => 1 } ) );
}

sub state_handle { return shift }  #XXX TODO better way to handle this?


sub _setup_repo_connection {
    my $self = shift;
    my %args = validate( @_, { repository => 1, db_uuid => 0 } );
    $self->fs_root( $args{'repository'} );
    $self->set_db_uuid( $args{'db_uuid'} ) if ( $args{'db_uuid'} );
    
    my $repos = eval {
        local $SIG{__DIE__} = 'DEFAULT';
        SVN::Repos::open( $self->fs_root );
    };
    # If we couldn't open the repository handle, we should create it
    if ( $@ && !-d $self->fs_root ) {
        $repos = SVN::Repos::create( $self->fs_root, undef, undef, undef, undef, $self->_pool );
    }
    $self->repo_handle($repos);
    $self->_determine_db_uuid;
    $self->_create_nonexistent_dir( $self->db_uuid );
}


=head2 uuid

Return the replica SVN repository's UUID

=cut

sub uuid {
    my $self = shift;
    return $self->repo_handle->fs->get_uuid;
}

sub latest_sequence_no {
    my $self = shift;
    Carp::cluck unless ($self->ra);
    $self->ra->get_latest_revnum;
}


sub traverse_changesets {
    my $self = shift;
    my %args = validate( @_,
        {   after    => 1,
            callback => 1,
        }
    );

    my $first_rev = ( $args{'after'} + 1 ) || 1;
    my $last_rev = $self->latest_sequence_no();


    die "You must implement latest_sequence_no in " . blessed($self) . ", or override traverse_changesets"
        unless defined $last_rev;

    for my $rev ( $first_rev .. $self->latest_sequence_no ) {
            my $changeset = $self->_fetch_changeset($rev);
        $args{callback}->( $changeset);
    }
}


sub _fetch_changeset {
    my $self   = shift;
    my $rev    = shift;

    require Prophet::Replica::SVN::ReplayEditor;
    my $editor = Prophet::Replica::SVN::ReplayEditor->new( _debug => 0 );
    my $pool = SVN::Pool->new_default;

    # This horrible hack is here because I have no idea how to pass custom variables into the editor
    $editor->{revision} = $rev;

    $self->ra->replay( $rev, 0, 1, $editor );
    return $self->_recode_changeset( $editor->dump_deltas, $self->ra->rev_proplist($rev) );

}

sub _recode_changeset {
    my $self      = shift;
    my $entry     = shift;
    my $revprops  = shift;
    my $changeset = Prophet::ChangeSet->new({
        creator              => $self->changeset_creator,
        sequence_no          => $entry->{'revision'},
        source_uuid          => $self->uuid,
        original_source_uuid => $revprops->{'prophet:original-source'} || $self->uuid,
        original_sequence_no => $revprops->{'prophet:original-sequence-no'} || $entry->{'revision'},
        is_nullification     => ( ( $revprops->{'prophet:special-type'} || '' ) eq 'nullification' ) ? 1 : undef,
        is_resolution        => ( ( $revprops->{'prophet:special-type'} || '' ) eq 'resolution' ) ? 1 : undef,
    });

    # add each record's changes to the changeset
    for my $path ( keys %{ $entry->{'paths'} } ) {
        if ( $path =~ qr|^(.+)/(.*?)/(.*?)$| ) {
            my ( $prefix, $type, $record ) = ( $1, $2, $3 );
            my $change = Prophet::Change->new(
                {   record_type   => $type,
                    record_uuid   => $record,
                    change_type => $entry->{'paths'}->{$path}->{fs_operation}
                }
            );
            for my $name ( keys %{ $entry->{'paths'}->{$path}->{prop_deltas} } ) {
                $change->add_prop_change(
                    name => $name,
                    old  => $entry->{paths}->{$path}->{prop_deltas}->{$name}->{'old'},
                    new  => $entry->{paths}->{$path}->{prop_deltas}->{$name}->{'new'},
                );
            }

            $changeset->add_change( change => $change );

        } else {
            warn "Discarding change to a non-record: $path" if 0;
        }

    }
    return $changeset;
}





=head1 CODE BELOW THIS LINE 

=cut

our $DEBUG = '0';
use Params::Validate qw(:all);



use constant can_read_records => 1;
use constant can_write_records => 1;
use constant can_read_changesets => 1;
use constant can_write_changesets => 1;


=head2 _current_root

Returns a handle to the svn filesystem's HEAD

=cut

sub _current_root {
    my $self = shift;
    $self->repo_handle->fs->revision_root( $self->repo_handle->fs->youngest_rev );
}

use constant USER_PROVIDED_DB_UUID => 1;
use constant DETECTED_DB_UUID      => 2;
use constant CREATED_DB_UUID       => 3;

sub _determine_db_uuid {
    my $self = shift;
    return USER_PROVIDED_DB_UUID if $self->db_uuid;
    my @known_replicas = keys %{ $self->_current_root->dir_entries("/") };

    for my $key ( keys %{ $self->_current_root->dir_entries("/") } ) {
        if ( $key =~ /^_prophet-/ ) {
            $self->set_db_uuid($key);
            return DETECTED_DB_UUID;
        }
    }

    # no luck. create one

    $self->set_db_uuid( "_prophet-" . Data::UUID->new->create_str() );
    return CREATED_DB_UUID;
}

sub _after_record_changes {
    my $self = shift;
    my ($changeset) = validate_pos( @_, { isa => 'Prophet::ChangeSet' } );

    $self->current_edit->change_prop( 'prophet:special-type' => 'nullification' ) if ( $changeset->is_nullification );
    $self->current_edit->change_prop( 'prophet:special-type' => 'resolution' )    if ( $changeset->is_resolution );
}


sub _set_original_source_metadata_for_current_edit {
    my $self = shift;
    my ($changeset) = validate_pos( @_, { isa => 'Prophet::ChangeSet' } );

    $self->current_edit->change_prop( 'prophet:original-source'      => $changeset->original_source_uuid );
    $self->current_edit->change_prop( 'prophet:original-sequence-no' => $changeset->original_sequence_no );
}

sub _create_nonexistent_dir {
    my $self = shift;
    my $dir  = shift;
    my $pool = SVN::Pool->new_default;
    my $root = $self->current_edit ? $self->current_edit->root : $self->_current_root;

    unless ( $root->is_dir($dir) ) {
        my $inside_edit = $self->current_edit ? 1 : 0;
        $self->begin_edit() unless ($inside_edit);
        $self->current_edit->root->make_dir($dir);
        $self->commit_edit() unless ($inside_edit);
    }
}




=head2 begin_edit

Starts a new transaction within the replica's backend database. Sets L</current_edit> to that edit object.

Returns $self->current_edit.

=cut

sub begin_edit {
    my $self = shift;
    my $fs   = $self->repo_handle->fs;
    $self->current_edit( $fs->begin_txn( $fs->youngest_rev ) );
    return $self->current_edit;
}

=head2 commit_edit

Finalizes L</current_edit> and sets the 'svn:author' change-prop to the current user.

=cut

sub commit_edit {
    my $self = shift;
    my $txn  = shift;
    $self->current_edit->change_prop( 'svn:author', ( $ENV{'PROPHET_USER'} || $ENV{'USER'} ) );
    $self->current_edit->commit;
    $self->current_edit(undef);

}

=head2 create_record { type => $TYPE, uuid => $uuid, props => { key-value pairs }}

Create a new record of type C<$type> with uuid C<$uuid>  within the current replica.

Sets the record's properties to the key-value hash passed in as the C<props> argument.

If called from within an edit, it uses the current edit. Otherwise it manufactures and finalizes one of its own.

=cut

sub create_record {
    my $self = shift;
    my %args = validate( @_, { uuid => 1, props => 1, type => 1 } );

    $self->_create_nonexistent_dir( join( '/', $self->db_uuid, $args{'type'} ) );

    my $inside_edit = $self->current_edit ? 1 : 0;
    $self->begin_edit() unless ($inside_edit);

    my $file = $self->_file_for( uuid => $args{uuid}, type => $args{'type'} );
    $self->current_edit->root->make_file($file);
    {
        my $stream = $self->current_edit->root->apply_text( $file, undef );

        # print $stream Dumper( $args{'props'} );
        close $stream;
    }
    $self->_set_record_props(
        uuid  => $args{uuid},
        props => $args{props},
        type  => $args{'type'}
    );
    $self->commit_edit() unless ($inside_edit);
    return 1;
}

sub _set_record_props {
    my $self = shift;
    my %args = validate( @_, { uuid => 1, props => 1, type => 1 } );

    my $file = $self->_file_for( uuid => $args{uuid}, type => $args{type} );
    foreach my $prop ( keys %{ $args{'props'} } ) {
        eval {
            local $SIG{__DIE__} = 'DEFAULT';
            $self->current_edit->root->change_node_prop( $file, $prop, $args{'props'}->{$prop}, undef )
        };
        Carp::confess($@) if ($@);
    }
}

=head2 delete_record {uuid => $uuid, type => $type }

Deletes the record C<$uuid> of type C<$type> from the current replica. 

Manufactures its own new edit if C<$self->current_edit> is undefined.

=cut

sub delete_record {
    my $self = shift;
    my %args = validate( @_, { uuid => 1, type => 1 } );

    my $inside_edit = $self->current_edit ? 1 : 0;
    $self->begin_edit() unless ($inside_edit);

    $self->current_edit->root->delete( $self->_file_for( uuid => $args{uuid}, type => $args{type} ) );
    $self->commit_edit() unless ($inside_edit);
    return 1;
}

=head2 set_record_props { uuid => $uuid, type => $type, props => {hash of kv pairs }}


Updates the record of type C<$type> with uuid C<$uuid> to set each property defined by the props hash. It does NOT alter any property not defined by the props hash.

Manufactures its own current edit if none exists.

=cut

sub set_record_props {
    my $self = shift;
    my %args = validate( @_, { uuid => 1, props => 1, type => 1 } );

    my $inside_edit = $self->current_edit ? 1 : 0;
    $self->begin_edit() unless ($inside_edit);

    my $file = $self->_file_for( uuid => $args{uuid}, type => $args{'type'} );
    $self->_set_record_props(
        uuid  => $args{uuid},
        props => $args{props},
        type  => $args{'type'}
    );
    $self->commit_edit() unless ($inside_edit);

}

=head2 get_record_props {uuid => $uuid, type => $type }

Returns a hashref of all properties for the record of type $type with uuid C<$uuid>.

=cut

sub get_record_props {
    my $self = shift;
    my %args = validate( @_, { uuid => 1, type => 1 } );
    return $self->_current_root->node_proplist( $self->_file_for( uuid => $args{'uuid'}, type => $args{'type'} ) );
}

=head2 _file_for { uuid => $UUID, type => $type }

Returns a file path within the repository (starting from the root)

=cut

sub _file_for {
    my $self = shift;
    my %args = validate( @_, { uuid => 1, type => 1 } );
    Carp::cluck unless $args{uuid};
    my $file = join( "/", $self->_directory_for_type( type => $args{'type'} ), $args{'uuid'} );
    return $file;

}

sub _directory_for_type {
    my $self = shift;
    my %args = validate( @_, { type => 1 } );
    Carp::cluck unless defined $args{type};
    return join( "/", $self->db_uuid, $args{'type'} );

}

=head2 record_exists {uuid => $uuid, type => $type, root => $root }

Returns true if the record in question exists. False otherwise

=cut

sub record_exists {
    my $self = shift;
    my %args = validate( @_, { uuid => 1, type => 1, root => undef } );

    my $root = $args{'root'} || $self->_current_root;
    return $root->check_path( $self->_file_for( uuid => $args{'uuid'}, type => $args{'type'} ) );

}

=head2 list_records { type => $type }

Returns a reference to a list of all the records of type $type

=cut

sub list_records {
    my $self = shift;
    my %args = validate( @_ => { type => 1 } );
    return [ keys %{ $self->_current_root->dir_entries( $self->db_uuid . '/' . $args{type} . '/' ) } ];
}

=head2 list_types

Returns a reference to a list of all the known types in your Prophet database

=cut

sub list_types {
    my $self = shift;
    return [ keys %{ $self->_current_root->dir_entries( $self->db_uuid . '/' ) } ];
}


=head2 type_exists { type => $type }

Returns true if we have any records of type C<$type>

=cut


sub type_exists {
    my $self = shift;
    my %args = validate( @_, { type => 1, root => undef } );

    my $root = $args{'root'} || $self->_current_root;
    return $root->check_path( $self->_directory_for_type( type => $args{'type'}, ) );

}

__PACKAGE__->meta->make_immutable;
no Moose;

1;

