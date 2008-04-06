use warnings;
use strict;

package Prophet::Handle::SVN;
use base qw/Prophet::Handle/;

use SVN::Core;
use SVN::Repos;
use SVN::Fs;

our $DEBUG = '0';
use Params::Validate qw(:all);

__PACKAGE__->mk_accessors(qw(repo_path repo_handle current_edit _pool));



sub new {
    my $class = shift;
    my $self  = {};
    bless $self, $class;
    
    my %args = validate( @_, { repository => 1, db_uuid => 0 } );
    $self->repo_path( $args{'repository'} );
    $self->_connect();
    $self->_pool( SVN::Pool->new );
    return $self;
}


=head2 uuid 

Returns the uuid of the repilica

=cut

sub uuid {
    my $self = shift;
    return $self->repo_handle->fs->get_uuid;
}



=head2 current_root

Returns a handle to the svn filesystem's HEAD

=cut

sub current_root {
    my $self = shift;
    $self->repo_handle->fs->revision_root( $self->repo_handle->fs->youngest_rev );
}

sub _connect {
    my $self = shift;
    my $repos = eval { SVN::Repos::open( $self->repo_path ); };

    # If we couldn't open the repository handle, we should create it
    if ( $@ && !-d $self->repo_path ) {
        $repos = SVN::Repos::create( $self->repo_path, undef, undef, undef, undef, $self->_pool );
    }

    $self->repo_handle($repos);
    $self->_create_nonexistent_dir( $self->db_uuid );
}


sub _cleanup_integrated_changeset{
    my $self = shift;
    my ($changeset) = validate_pos(@_, { isa => 'Prophet::ChangeSet'});
            
        $self->current_edit->change_prop( 'prophet:special-type' => 'nullification' )            if ( $changeset->is_nullification );
        $self->current_edit->change_prop( 'prophet:special-type' => 'resolution' ) if ( $changeset->is_resolution );
}


sub record_changeset_integration {
    my $self = shift;
    my ($changeset) = validate_pos( @_, { isa => 'Prophet::ChangeSet' } );

    $self->_set_original_source_metadata($changeset);
    return $self->SUPER::record_changeset_integration($changeset);

}


sub _set_original_source_metadata {
    my $self   = shift;
      my ($changeset) = validate_pos( @_, { isa => 'Prophet::ChangeSet' } );

    $self->current_edit->change_prop( 'prophet:original-source'      => $changeset->original_source_uuid );
    $self->current_edit->change_prop( 'prophet:original-sequence-no' => $changeset->original_sequence_no );
}


sub _create_nonexistent_dir {
    my $self = shift;
    my $dir  = shift;
    my $pool = SVN::Pool->new_default;
    my $root = $self->current_edit ? $self->current_edit->root : $self->current_root;

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



=head2 create_node { type => $TYPE, uuid => $uuid, props => { key-value pairs }}

Create a new record of type C<$type> with uuid C<$uuid>  within the current replica.

Sets the record's properties to the key-value hash passed in as the C<props> argument.

If called from within an edit, it uses the current edit. Otherwise it manufactures and finalizes one of its own.

=cut

sub create_node {
    my $self = shift;
    my %args = validate( @_, { uuid => 1, props => 1, type => 1 } );

    $self->_create_nonexistent_dir( join( '/', $self->db_uuid, $args{'type'} ) );

    my $inside_edit = $self->current_edit ? 1 : 0;
    $self->begin_edit() unless ($inside_edit);

    my $file = $self->file_for( uuid => $args{uuid}, type => $args{'type'} );
    $self->current_edit->root->make_file($file);
    {
        my $stream = $self->current_edit->root->apply_text( $file, undef );

        # print $stream Dumper( $args{'props'} );
        close $stream;
    }
    $self->_set_node_props(
        uuid  => $args{uuid},
        props => $args{props},
        type  => $args{'type'}
    );
    $self->commit_edit() unless ($inside_edit);

}

sub _set_node_props {
    my $self = shift;
    my %args = validate( @_, { uuid => 1, props => 1, type => 1 } );

    my $file = $self->file_for( uuid => $args{uuid}, type => $args{type} );
    foreach my $prop ( keys %{ $args{'props'} } ) {
        eval { $self->current_edit->root->change_node_prop( $file, $prop, $args{'props'}->{$prop}, undef ) };
        Carp::confess($@) if ($@);
    }
}

=head2 delete_node {uuid => $uuid, type => $type }

Deletes the node C<$uuid> of type C<$type> from the current replica. 

Manufactures its own new edit if C<$self->current_edit> is undefined.

=cut

sub delete_node {
    my $self = shift;
    my %args = validate( @_, { uuid => 1, type => 1 } );

    my $inside_edit = $self->current_edit ? 1 : 0;
    $self->begin_edit() unless ($inside_edit);

    $self->current_edit->root->delete( $self->file_for( uuid => $args{uuid}, type => $args{type} ) );
    $self->commit_edit() unless ($inside_edit);
    return 1;
}

=head2 set_node_props { uuid => $uuid, type => $type, props => {hash of kv pairs }}


Updates the record of type C<$type> with uuid C<$uuid> to set each property defined by the props hash. It does NOT alter any property not defined by the props hash.

Manufactures its own current edit if none exists.

=cut

sub set_node_props {
    my $self = shift;
    my %args = validate( @_, { uuid => 1, props => 1, type => 1 } );

    my $inside_edit = $self->current_edit ? 1 : 0;
    $self->begin_edit() unless ($inside_edit);

    my $file = $self->file_for( uuid => $args{uuid}, type => $args{'type'} );
    $self->_set_node_props(
        uuid  => $args{uuid},
        props => $args{props},
        type  => $args{'type'}
    );
    $self->commit_edit() unless ($inside_edit);

}



=head2 get_node_props {uuid => $uuid, type => $type, root => $root }

Returns a hashref of all properties for the record of type $type with uuid C<$uuid>.

'root' is an optional argument which you can use to pass in an alternate historical version of the replica to inspect.  Code to look at the immediately previous version of a record might look like:

    $handle->get_node_props(
        type => $record->type,
        uuid => $record->uuid,
        root => $self->repo_handle->fs->revision_root( $self->repo_handle->fs->youngest_rev - 1 )
    );


=cut

sub get_node_props {
    my $self = shift;
    my %args = validate( @_, { uuid => 1, type => 1, root => undef } );
    my $root = $args{'root'} || $self->current_root;
    return $root->node_proplist( $self->file_for( uuid => $args{'uuid'}, type => $args{'type'} ) );
}






=head2 file_for { uuid => $UUID, type => $type }

Returns a file path within the repository (starting from the root)

=cut

sub file_for {
    my $self = shift;
    my %args = validate( @_, { uuid => 1, type => 1 } );
    Carp::cluck unless $args{uuid};
    my $file = join( "/", $self->directory_for_type( type => $args{'type'} ), $args{'uuid'} );
    return $file;

}

sub directory_for_type {
    my $self = shift;
    my %args = validate( @_, { type => 1 } );
    Carp::cluck unless defined $args{type};
    return join( "/", $self->db_uuid, $args{'type'} );

}



=head2 node_exists {uuid => $uuid, type => $type, root => $root }

Returns true if the node in question exists. False otherwise

=cut

sub node_exists {
    my $self = shift;
    my %args = validate( @_, { uuid => 1, type => 1, root => undef } );

    my $root = $args{'root'} || $self->current_root;
    return $root->check_path( $self->file_for( uuid => $args{'uuid'}, type => $args{'type'} ) );

}
sub enumerate_nodes {
    my $self = shift;
    my %args = validate(@_ => { type => 1 } );
   return $self->current_root->dir_entries( $self->db_uuid . '/' . $args{type} . '/' );
}


sub type_exists {
    my $self = shift;
    my %args = validate( @_, { type => 1, root => undef } );

    my $root = $args{'root'} || $self->current_root;
    return $root->check_path( $self->directory_for_type( type => $args{'type'}, ) );

}



1;

