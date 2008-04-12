use warnings;
use strict;

package Prophet::App;
use base qw/Class::Accessor/;
use Path::Class;
__PACKAGE__->mk_accessors(qw/_resdb_handle/);

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
        $self->_handle( Prophet::Replica->new( { url => 'svn:file://' . $root } ) );
    }
    return $self->_handle();
}

=head2 resdb_handle

=cut

sub resdb_handle {
    my $self = shift;
    unless ( $self->_resdb_handle ) {
        my $root = ( $ENV{'PROPHET_REPO'} || dir( $ENV{'HOME'}, '.prophet' ) ) . "_res";
        $self->_resdb_handle( Prophet::Replica->new( { url => 'svn:file://' . $root } ) );
    }
    return $self->_resdb_handle();
}


1;
