use warnings;
use strict;


package Prophet::App;
use base qw/Class::Accessor/;

__PACKAGE__->mk_accessors(qw/_handle _resdb_handle/);

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
    unless ( $self->_handle ) {
        my $root = $ENV{'PROPHET_REPO'} || dir( $ENV{'HOME'}, '.prophet' );
        $self->_handle( Prophet::Handle->new( repository => $root ) );
    }
    return $self->_handle();
}

=head2 resdb_handle

=cut

sub resdb_handle {
    my $self = shift;
    unless ( $self->_resdb_handle ) {
        my $root = ( $ENV{'PROPHET_REPO'} || dir( $ENV{'HOME'}, '.prophet' ) ) . "_res";
        $self->_resdb_handle( Prophet::Handle->new( repository => $root ) );
    }
    return $self->_resdb_handle();
}

=head2 get_handle_for_replica($replica, $db_root)

for a foreign $replica, this returns a Prophet::Handle for local storage that are based in db_root

=cut

sub get_handle_for_replica {
    my ( $self, $replica, $db_uuid ) = @_;
    my $root = $ENV{'PROPHET_REPO'} || dir( $ENV{'HOME'}, '.prophet' ) . '/_prophet_replica/' . $replica->uuid;
    return Prophet::Handle->new( repository => $root, db_uuid => $db_uuid );
}

1;
