use warnings;
use strict;

package Prophet::Handle;
use base 'Class::Accessor';
use Params::Validate;
use Data::Dumper;
use Data::UUID;

use Prophet::Editor;
use SVN::Core;
use SVN::Repos;
use SVN::Fs;

__PACKAGE__->mk_accessors(qw(repo_path repo_handle db_root));

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

sub current_root {
    my $self = shift;
    $self->repo_handle->fs->revision_root(
        $self->repo_handle->fs->youngest_rev );
}

sub _connect {
    my $self = shift;

    my $repos;
    eval {
        $repos = SVN::Repos::open( $self->repo_path );

    };

    if ( $@ && !-d $self->repo_path ) {
        $repos = SVN::Repos::create( $self->repo_path, undef, undef, undef,
            undef );

    }
    $self->repo_handle($repos);
    $self->_create_nonexistent_dir( $self->db_root );
}

sub _create_nonexistent_dir {
    my $self = shift;
    my $dir  = shift;
    unless ( $self->current_root->is_dir($dir) ) {
        my $edit = $self->begin_edit;
        $edit->root->make_dir($dir);
        $self->commit_edit($edit);
    }

}

sub begin_edit {
    my $self = shift;
    my $fs   = $self->repo_handle->fs;
    my $txn  = $fs->begin_txn( $fs->youngest_rev );

    return $txn;
}

sub commit_edit {
    my $self = shift;
    my $txn  = shift;
    $txn->change_prop( 'svn:author', $ENV{'USER'} );
    $txn->commit;

}

sub create_node {
    my $self = shift;
    my %args = validate( @_, { uuid => 1, props => 1, type => 1 } );
    $self->_create_nonexistent_dir(
        join( '/', $self->db_root, $args{'type'} ) );
    my $edit = $self->begin_edit();

    my $file = $self->file_for( uuid => $args{uuid}, type => $args{'type'} );
    $edit->root->make_file($file);
    {
        my $stream = $edit->root->apply_text( $file, undef );
        print $stream Dumper( $args{'props'} );
        close $stream;
    }
    $self->_set_node_props(
        uuid  => $args{uuid},
        props => $args{props},
        edit  => $edit,
        type  => $args{'type'}
    );
    $self->commit_edit($edit);

}

sub _set_node_props {
    my $self = shift;
    my %args
        = validate( @_, { uuid => 1, props => 1, edit => 1, type => 1 } );
    my $file = $self->file_for( uuid => $args{uuid}, type => $args{type} );
    foreach my $prop ( keys %{ $args{'props'} } ) {
        $args{edit}
            ->root->change_node_prop( $file, $prop, $args{'props'}->{$prop},
            undef );
    }
}

sub delete_node {
    my $self = shift;
    my %args = validate( @_, { uuid => 1, type => 1 } );
    my $edit = $self->begin_edit();
    $edit->root->delete(
        $self->file_for( uuid => $args{uuid}, type => $args{type} ) );
    $self->commit_edit($edit);

}

sub set_node_props {
    my $self = shift;
    my %args = validate( @_, { uuid => 1, props => 1, type => 1 } );
    my $edit = $self->begin_edit();
    my $file = $self->file_for( uuid => $args{uuid}, type => $args{'type'} );
    $self->_set_node_props(
        uuid  => $args{uuid},
        props => $args{props},
        edit  => $edit,
        type  => $args{'type'}
    );
    $self->commit_edit($edit);

}

sub get_node_props {
    my $self = shift;
    my %args = validate( @_, { uuid => 1, type => 1, root => undef } );
    my $root = $args{'root'} || $self->current_root;
    return $root->node_proplist(
        $self->file_for( uuid => $args{'uuid'}, type => $args{'type'} ) );
}

sub file_for {
    my $self = shift;
    my %args = validate( @_, { uuid => 1, type => 1 } );
    my $file = join( "/", $self->db_root, ,$args{'type'}, $args{'uuid'} );
    return $file;

}


my $MERGETICKET_METATYPE = '_merge_tickets';
sub last_changeset_for_source {
    my $self = shift;
    my %args = validate( @_, { source => 1, } );

    my %props = $self->get_node_props(uuid => $args{'source'}, type => $MERGETICKET_METATYPE);
    
    return $props{'last-rev'};



}

sub record_changeset_for_source {
    my $self = shift;
    my %args = validate( @_, { source => 1,  changeset => 1} );
    my %props = $self->get_node_props(uuid => $args{'source'}, type => $MERGETICKET_METATYPE);
    unless ($props{'last-rev'}) {
            $self->create_node( uuid => $args{'source'}, type => $MERGETICKET_METATYPE );
    }
    $self->set_node_props(uuid => $args{'source'}, type => $MERGETICKET_METATYPE, props => { 'last-rev' => $args{'changeset'}});

}



1;
