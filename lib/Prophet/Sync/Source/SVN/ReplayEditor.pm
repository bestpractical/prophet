use warnings;
use strict;

package Prophet::Sync::Source::SVN::ReplayEditor;
use base qw/SVN::Delta::Editor/;
our $CURRENT_REMOTE_REVNO;

=head1 NAME

Prophet::Sync::Source::SVN::ReplayEditor

=head1 DESCRIPTION

This class encapsulates a Subversion "replay" editor.  Prophet's
Subversion synchronization client (L<Prophet::Sync::Source::SVN>)
uses it to turn a set of subversion
deltas into a set of L<Prophet::ChangeSet> objects.


=head1 METHODS

=cut

=head2 new

Instantiates a new subversion "editor" to track a single remote revision


=cut

sub new {
    my $self = shift->SUPER::new(@_);
    $self->{'revision'} = $CURRENT_REMOTE_REVNO;
    return $self;
}

=head2 ra [$RA]

Gets or sets the Subversion RA object.

=cut

sub ra {
    my $self = shift;
    $self->{'_ra'} = shift if (@_);
    return $self->{'_ra'};

}

=head2 open_root  ($edit_baton, $base_rev, $dir_pool, $root_baton)

Called by subversion at the beginning of any edit. We only care about the base_rev

=cut


sub open_root {
    my $self = shift;
    my ($edit_baton, $base_rev, $dir_pool, $root_baton) = (@_);
    $self->{'base_rev'} = $base_rev;
}

=head2 open_directory($path, $parent_baton, $base_rev, $dir_pool, $child_baton) 

Called by the subversion RA layer each time SVN descends into a new directory within an open edit.
Pushes the directory onto the internal L</dir_stack>

=cut

sub open_directory { 
    my $self = shift;
    my ($path, $parent_baton, $base_rev, $dir_pool, $child_baton) = (@_);
    push @{$self->{'dir_stack'}}, { path => $path, base_rev => $base_rev};
}

=head2 delete_entry ($path, $revision, $parent_baton)

Called for any file/directory deleted within this edit.

=cut

sub delete_entry { 
    my $self = shift;
    my ($path, $revision, $parent_baton) = (@_);
    $self->{'paths'}->{$path}->{fs} = 'delete';
}

=head2 add_file ($path, $parent_baton, $copy_path, $copy_revision, $file_pool, $file_baton) 

Called whenever a file is added within an edit.

=cut

sub add_file { 
    my $self = shift;
    my ($path, $parent_baton, $copy_path, $copy_revision, $file_pool, $file_baton) = (@_);
    $self->{'current_file'} = $path;
    $self->{'current_file_base_rev'} = "newly created";
    $self->{'paths'}->{$path}->{fs} = 'add_file';
}

=head2 add_file ($path, $parent_baton, $copy_path, $copy_revision, $dir_pool, $child_baton) 

Called whenever a directory is added within an edit.

=cut


sub add_directory {
    my $self = shift;
    my ($path, $parent_baton, $copyfrom_path, $copyfrom_revision, $dir_pool, $child_baton) = (@_);
    push @{$self->{'dir_stack'}}, { path => $path, base_rev => -1 };
    $self->{'paths'}->{$path}->{fs} = 'add_dir';
}



=head2 open_file  ($path, $parent_baton, $base_rev, $file_pool, $file_baton) 

Called whenever a file is opened for writing within the current
edit. This routine sets the context of future content or property
changes.

=cut

sub open_file {
    my $self = shift;
    my ($path, $parent_baton, $base_rev, $file_pool, $file_baton) = (@_);

    $self->{'current_file'} = $path;
    $self->{'current_file_base_rev'} = $base_rev;

    my ($stream, $pool);
    my ($rev_fetched, $prev_props)  =  $self->ra->get_file($path, $self->{'revision'}-1, $stream,$pool);

    $self->{'paths'}->{$path}->{fs} = 'update_file';
    $self->{'paths'}->{$path}->{prev_properties} = $prev_props;
}


=head2 close_file ($file_baton, $text_checksum,$pool)

Called when all edits to a file are complete. This routine ends the 'current file' context

=cut


sub close_file {
    my $self = shift;
    my ($file_baton, $text_checksum, $pool) = (@_);
    delete $self->{'current_file'};
    delete $self->{'current_file_base_rev'}; 

}

#sub absent_file {
#    my $self = shift;
#    my ($file_baton, $text_checksum, $pool) = (@_);
#}

=head2 close_directory ($dir_baton, $pool)

Called by Subversion to indicate that all edits inside a directory have been completed

=cut

sub close_directory {
    my $self = shift;
    my ($dir_baton, $pool) = (@_);
    pop @{$self->{dir_stack}};
}

#sub absent_directory {
#    my $self = shift;
#    my ($path, $parent_baton, $pool) = (@_);
#}


=head2 change_file_prop ($baton, $name, $value,$pool)

Called by Subversion when a file property changes. All Subversion
tells us is that 'the current node's property called $name has
changed to $value'. This routine roots around and builds a delta
from the previous value to the new value.

=cut

sub change_file_prop {
    my $self = shift;
    my ( $file_baton, $name, $value, $pool ) = (@_);

    $self->{'paths'}->{ $self->{'current_file'} }->{prop_deltas}->{$name} = {
        old => $self->{'paths'}->{ $self->{'current_file'} }->{'prev_properties'}->{$name},
        new => $value
    };
}

=head2 change_file_prop ($baton, $name, $value,$pool)

Called by Subversion when a directory property changes. All Subversion
tells us is that 'the current node's property called $name has
changed to $value'. This routine roots around and builds a delta
from the previous value to the new value.

=cut


sub change_dir_prop {
    my $self = shift;
    my ($dir_baton, $name, $value, $pool) = (@_);
    $self->{'paths'}->{ $self->{'dir_stack'}->[-1]->{path} }->{prop_deltas}->{$name} = {
        old => $self->{'paths'}->{ $self->{'dir_stack'}->[-1]->{path} }->{'prev_properties'}->{$name},
        new => $value
        };

}



#sub close_edit {
#    my $self = shift;
#    my ($edit_baton, $pool) = (@_); 
#}


=head2 dump_deltas

Returns a data structure describiing the revision and all the changes made to it:

 { revision => 1234,
   paths => { 'foo' => { ... } 
            }
   }

        

=cut


sub dump_deltas{
    my $self = shift;
    return { revision => $self->{'revision'}, paths => $self->{'paths'}}

}

1;

