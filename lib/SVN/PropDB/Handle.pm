use warnings;
use strict;

package SVN::PropDB::Handle;
use base 'Class::Accessor';
use Params::Validate;
use Data::Dumper;
use Data::UUID;

use SVN::PropDB::Editor;
use SVN::Core;
use SVN::Repos;
use SVN::Fs;

__PACKAGE__->mk_accessors(qw(repo_path repo_handle));

sub new {
    my $class = shift;
    my $self  = {};
    bless $self, $class;
    my %args = validate( @_, { repository => 1 } );

    $self->repo_path( $args{'repository'} );
    $self->_connect();

    return $self;
}

our $MYROOT = '/_propdb';
sub current_root {
    my $self = shift;
     $self->repo_handle->fs->revision_root ($self->repo_handle->fs->youngest_rev);
}



sub _connect {
    my $self  = shift;
    my $repos = SVN::Repos::open( $self->repo_path );
    warn "opened the repos";
    $self->repo_handle($repos);
    unless($self->current_root->is_dir($MYROOT)) {
    my $edit = $self->begin_edit;
    $edit->root->make_dir($MYROOT);
    $self->commit_edit($edit);
    }

}

sub begin_edit {
    my $self = shift;
    my $fs = $self->repo_handle->fs;
    my $txn = $fs->begin_txn($fs->youngest_rev);

    return $txn;
}

sub commit_edit {
    my $self = shift;
    my $txn = shift;
    $txn->commit;

}

sub create_node {
    my $self = shift;
    my %args = validate( @_, { uuid => 1, props => 1 } );
    my $edit = $self->begin_edit();
    my $file = $self->file_for(uuid => $args{uuid});
    $edit->root->make_file( $file );
    {
        my $stream = $edit->root->apply_text($file, undef);
        print $stream Dumper($args{'props'});
        close $stream;
    }
    $self->_set_node_props(uuid => $args{uuid}, props => $args{props}, edit => $edit);
    $self->commit_edit($edit);

}

sub _set_node_props {
my $self = shift;
    my %args = validate(@_, { uuid => 1, props=> 1, edit => 1});
    my $file = $self->file_for(uuid => $args{uuid});
    foreach my $prop (keys %{$args{'props'}}) {
        $args{edit}->root->change_node_prop($file,$prop, $args{'props'}->{$prop}, undef);
    }
}

sub delete_node {
    my $self = shift;
    my %args = validate( @_, { uuid => 1 } );

}

sub set_node_props {
    my $self = shift;
    my %args = validate( @_, { uuid => 1, props => 1 } );
    my $edit = $self->begin_edit();
    my $file = $self->file_for(uuid => $args{uuid});
    $self->_set_node_props(uuid => $args{uuid}, props => $args{props} ,edit => $edit);
    $self->commit_edit($edit);

}

    

sub get_node_props {
    my $self = shift;
    my %args = validate( @_, { uuid => 1,  } );
    return $self->current_root->node_proplist($self->file_for(uuid => $args{'uuid'}));
}



sub file_for {
my $self = shift;
    my %args = validate( @_, { uuid => 1,  } );
    my $file = $MYROOT."/".$args{'uuid'};
    return $file;

}

1;
