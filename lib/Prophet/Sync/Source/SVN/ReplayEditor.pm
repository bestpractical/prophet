use warnings;
use strict;

package Prophet::Sync::Source::SVN::ReplayEditor;
use base qw/SVN::Delta::Editor/;
our $CURRENT_REMOTE_REVNO;

sub new {
    my $self = shift->SUPER::new(@_);
    $self->{'revision'} = $CURRENT_REMOTE_REVNO;
    return $self;
}



sub ra {
    my $self = shift;
    $self->{'_ra'} = shift if (@_);
    return $self->{'_ra'};

}


sub open_root {
    my $self = shift;
    my ($edit_baton, $base_rev, $dir_pool, $root_baton) = (@_);
    $self->{'base_rev'} = $base_rev;
}


sub open_directory { 
    my $self = shift;
    my ($path, $parent_baton, $base_rev, $dir_pool, $child_baton) = (@_);
    push @{$self->{'dir_stack'}}, { path => $path, base_rev => $base_rev};
}
sub delete_entry { 
    my $self = shift;
    my ($path, $revision, $parent_baton) = (@_);
    $self->{'paths'}->{$path}->{fs} = 'delete';
}

sub add_file { 
    my $self = shift;
    my ($path, $parent_baton, $copy_path, $copy_revision, $file_pool, $file_baton) = (@_);
    $self->{'current_file'} = $path;
    $self->{'current_file_base_rev'} = "newly created";
    $self->{'paths'}->{$path}->{fs} = 'add_file';
}

sub add_directory {
    my $self = shift;
    my ($path, $parent_baton, $copyfrom_path, $copyfrom_revision, $dir_pool, $child_baton) = (@_);
    push @{$self->{'dir_stack'}}, { path => $path, base_rev => -1 };
    $self->{'paths'}->{$path}->{fs} = 'add_dir';
}

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



sub close_file {
    my $self = shift;
    my ($file_baton, $text_checksum, $pool) = (@_);
    delete $self->{'current_file'};
    delete $self->{'current_file_base_rev'}; 

}

sub absent_file {
    my $self = shift;
    my ($file_baton, $text_checksum, $pool) = (@_);
}

sub close_directory {
    my $self = shift;
    my ($dir_baton, $pool) = (@_);
    pop @{$self->{dir_stack}};
}

sub absent_directory {
    my $self = shift;
    my ($path, $parent_baton, $pool) = (@_);
}

sub change_file_prop {
    my $self = shift;
    my ( $file_baton, $name, $value, $pool ) = (@_);

    $self->{'paths'}->{ $self->{'current_file'} }->{prop_deltas}->{$name} = {
        old => $self->{'paths'}->{ $self->{'current_file'} }->{'prev_properties'}->{$name},
        new => $value
    };
}

sub change_dir_prop {
    my $self = shift;
    my ($dir_baton, $name, $value, $pool) = (@_);
    $self->{'paths'}->{ $self->{'dir_stack'}->[-1]->{path} }->{prop_deltas}->{$name} = {
        old => $self->{'paths'}->{ $self->{'dir_stack'}->[-1]->{path} }->{'prev_properties'}->{$name},
        new => $value
        };

}


sub close_edit {
    my $self = shift;
    my ($edit_baton, $pool) = (@_); 
}


sub dump_deltas{
    my $self = shift;
    return { revision => $self->{'revision'}, paths => $self->{'paths'}}

}

1;

