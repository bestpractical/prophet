use warnings;
use strict;

package Prophet::Replica::FS;
use base qw/Prophet::Replica/;


use constant scheme => 'svn';

sub setup {

} 

sub state_handle { return shift }  #XXX TODO better way to handle this?
sub uuid {
    my $self = shift;
}
sub latest_sequence_no {
    my $self = shift;
}
sub fetch_changeset {
    my ($self,$changeset_id) = validate_pos(@_,1,1);

    my $changeset = Prophet::ChangeSet->new(); #
    return $changeset; # a Prophet::ChangeSet
}
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
    my %args = validate( @_, { uuid => 1, props => 1, type => 1 } );

}
sub delete_record {
    my $self = shift;
    my %args = validate( @_, { uuid => 1, type => 1 } );
}
sub set_record_props {
    my $self = shift;
    my %args = validate( @_, { uuid => 1, props => 1, type => 1 } );

}
sub get_record_props {
    my $self = shift;
    my %args = validate( @_, { uuid => 1, type => 1 } );
}
sub record_exists {
    my $self = shift;
    my %args = validate( @_, { uuid => 1, type => 1, root => undef } );
}
sub list_records {
    my $self = shift;
    my %args = validate( @_ => { type => 1 } );
}
sub list_types {
    my $self = shift;
}
sub type_exists {
    my $self = shift;
    my %args = validate( @_, { type => 1, root => undef } );
}


 1;
