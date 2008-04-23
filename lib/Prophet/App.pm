use warnings;
use strict;

package Prophet::App;
use base qw/Class::Accessor/;
use Path::Class;
__PACKAGE__->mk_accessors(qw/_resdb_handle/);

use constant DEFAULT_REPLICA_TYPE => 'prophet';


sub _handle {
    my $self = shift;
    $self->{_handle} = shift if (@_);
    return $self->{_handle};
}

sub new {
    my $self = shift->SUPER::new(@_);

    # Initialize our handle and resolution db handle
    $self->handle;
    $self->resdb_handle;

    return $self;
}

=head2 handle


=cut

sub handle {
    my $self = shift;
    unless ( $self->_handle() ) {
        my $root = $ENV{'PROPHET_REPO'} || dir( $ENV{'HOME'}, '.prophet' );
        my $type = $ENV{'PROPHET_REPLICA_TYPE'} || DEFAULT_REPLICA_TYPE;
        $self->_handle( Prophet::Replica->new( { url => $type.':file://' . $root } ) );
    }
    return $self->_handle();
}

=head2 resdb_handle

=cut

sub resdb_handle {
    my $self = shift;
   
    return ($self->handle->resolution_db_handle) if ($self->handle->resolution_db_handle);
    unless ( $self->_resdb_handle ) {
        my $root = ( $ENV{'PROPHET_REPO'} || dir( $ENV{'HOME'}, '.prophet' ) ) . "_res";
        my $type = $ENV{'PROPHET_REPLICA_TYPE'} || DEFAULT_REPLICA_TYPE;
        $self->_resdb_handle( Prophet::Replica->new( { url => $type.':file://' . $root } ) );
    }
    return $self->_resdb_handle();
}



1;
