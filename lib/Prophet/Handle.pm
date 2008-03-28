use warnings;
use strict;

package Prophet::Handle;
use base 'Class::Accessor';
use Params::Validate;
use Data::Dumper;
use Data::UUID;

use SVN::Core;
use SVN::Repos;
use SVN::Fs;

__PACKAGE__->mk_accessors(qw(repo_path repo_handle db_root current_edit));


=head2 new { repository => $FILESYSTEM_PATH, db_root => $REPOS_PATH }
 
Create a new subversion filesystem backend repository handle. If the repository/path don't exist, create it.

=cut

sub new {
    my $class = shift;
    my $self  = {};
    bless $self, $class;
    my %args = validate( @_, { repository => 1, db_root => 1 } );
    $self->db_root( $args{'db_root'} );
    $self->repo_path( $args{'repository'} );
    $self->_connect();

    return $self;
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
    if ( $@ && ! -d $self->repo_path ) {
        $repos = SVN::Repos::create( $self->repo_path, undef, undef, undef, undef );
    }

    $self->repo_handle($repos);
    $self->_create_nonexistent_dir( $self->db_root );
}

sub _create_nonexistent_dir {
    my $self = shift;
    my $dir  = shift;
    unless ( $self->current_root->is_dir($dir) ) {
        my $inside_edit = $self->current_edit ? 1: 0;
        $self->begin_edit() unless ($inside_edit);
        $self->current_edit->root->make_dir($dir);
        $self->commit_edit() unless ($inside_edit);
    }
}

sub begin_edit {
    my $self = shift;
    my $fs   = $self->repo_handle->fs;
    $self->current_edit( $fs->begin_txn( $fs->youngest_rev ));
    return $self->current_edit;
}

sub commit_edit {
    my $self = shift;
    my $txn  = shift;
    $self->current_edit->change_prop( 'svn:author', $ENV{'USER'} );
    $self->current_edit->commit;
    $self->current_edit(undef);

}


sub integrate_changeset {
    my $self      = shift;
    my $changeset = shift;

    $self->begin_edit();
    $self->_integrate_change($_) for ($changeset->changes);
    $self->_set_original_source_metadata($changeset);
    $self->commit_edit();
}

sub _set_original_source_metadata {
    my $self = shift;
    my $change = shift;

    $self->current_edit->change_prop( 'prophet:original-source'  => $change->original_source_uuid  ||$change->source_uuid );
    $self->current_edit->change_prop( 'prophet:original-sequence-no'  => $change->original_sequence_no  ||$change->sequence_no);
}




sub _integrate_change {
    my $self   = shift;
    my $change = shift;

    my %new_props = map { $_->name => $_->new_value } $change->prop_changes;

    if ( $change->change_type eq 'add_file' ) {
        $self->create_node(
            type  => $change->node_type,
            uuid  => $change->node_uuid,
            props => \%new_props
        );
    } elsif ( $change->change_type eq 'add_dir' ) {
    } elsif ( $change->change_type eq 'update_file' ) {
        $self->set_node_props(
            type  => $change->node_type,
            uuid  => $change->node_uuid,
            props => \%new_props
        );
    } elsif ( $change->change_type eq 'delete' ) {
        $self->delete_node(
            type => $change->node_type,
            uuid => $change->node_uuid
        );
    }
}



sub create_node {
    my $self = shift;
    my %args = validate( @_, { uuid => 1, props => 1, type => 1 } );

    $self->_create_nonexistent_dir( join( '/', $self->db_root, $args{'type'} ) );

    my $inside_edit = $self->current_edit ? 1: 0;
    $self->begin_edit() unless ($inside_edit);

    my $file = $self->file_for( uuid => $args{uuid}, type => $args{'type'} );
    $self->current_edit->root->make_file($file);
    {
        my $stream = $self->current_edit->root->apply_text( $file, undef );
        print $stream Dumper( $args{'props'} );
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
        $self->current_edit->root->change_node_prop( $file, $prop, $args{'props'}->{$prop}, undef );
    }
}

sub delete_node {
    my $self = shift;
    my %args = validate( @_, { uuid => 1, type => 1 } );

    my $inside_edit = $self->current_edit ? 1: 0;
    $self->begin_edit() unless ($inside_edit);

     $self->current_edit->root->delete( $self->file_for( uuid => $args{uuid}, type => $args{type} ) );
    $self->commit_edit() unless ($inside_edit);
    return 1;
}

sub set_node_props {
    my $self = shift;
    my %args = validate( @_, { uuid => 1, props => 1, type => 1 } );

    my $inside_edit = $self->current_edit ? 1: 0;
    $self->begin_edit() unless ($inside_edit);
    
    my $file = $self->file_for( uuid => $args{uuid}, type => $args{'type'} );
    $self->_set_node_props(
        uuid  => $args{uuid},
        props => $args{props},
        type  => $args{'type'}
    );
    $self->commit_edit() unless ($inside_edit);

}

sub get_node_props {
    my $self = shift;
    my %args = validate( @_, { uuid => 1, type => 1, root => undef } );

    my $root = $args{'root'} || $self->current_root;
    return $root->node_proplist( $self->file_for( uuid => $args{'uuid'}, type => $args{'type'} ) );
}

sub file_for {
    my $self = shift;
    my %args = validate( @_, { uuid => 1, type => 1 } );
    my $file = join( "/", $self->db_root, ,$args{'type'}, $args{'uuid'} );
    return $file;

}


our $MERGETICKET_METATYPE = '_merge_tickets';

sub last_changeset_from_source {
    my $self = shift;
    my ($source)  = validate_pos( @_, { isa => 'Prophet::Sync::Source' } );
    my $props = eval {$self->get_node_props(uuid => $source->uuid, type => $MERGETICKET_METATYPE)};
    return $props->{'last-changeset'};

}

sub record_changeset_integration {
    my $self = shift;
    my ($changeset) = validate_pos( @_, { isa => 'Prophet::ChangeSet' } );

    # Record a merge ticket for the changeset's "direct" source
    $self->_record_merge_ticket( $changeset->source_uuid, $changeset->sequence_no );

    # Record a merge ticket for the changeset's "original" source
    $self->_record_merge_ticket( $changeset->original_source_uuid, $changeset->original_sequence_no )
        if ( $changeset->original_source_uuid && $changeset->original_source_uuid ne $changeset->source_uuid );

}

sub _record_merge_ticket {
    my $self = shift;
    my ($source_uuid, $sequence_no) = validate_pos(@_, 1,1);

    my $props = eval { $self->get_node_props( uuid => $source_uuid, type => $MERGETICKET_METATYPE ) };
    unless ( $props->{'last-changeset'} ) {
        eval { $self->create_node( uuid => $source_uuid, type => $MERGETICKET_METATYPE, props => {} ) };
    }

    $self->set_node_props(
        uuid  => $source_uuid,
        type  => $MERGETICKET_METATYPE,
        props => { 'last-changeset' => $sequence_no }
    );

}



1;
