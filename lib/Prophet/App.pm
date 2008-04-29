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
   
    $self->_load_replica_types();

    # Initialize our handle and resolution db handle
    $self->handle;
    $self->resdb_handle;

    return $self;
}

sub _load_replica_types {
    my $self = shift;
        my $replica_class = ref($self)."::Replica";
        my $except = $replica_class."::(.*)::";
        Module::Pluggable->import( search_path => $replica_class, sub_name => 'app_replica_types', require => 0, except => qr/$except/);
        for my $package ( $self->app_replica_types) {
            $package->require;
        Prophet::Replica->register_replica_scheme(scheme => $package->scheme, class => $package) 
        }
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


sub require_module {
    my $self = shift;
    my $class = shift;
    $class->require;
    if (my $msg = $@) {
        my $class_path = $class .".pm";
        $class_path =~ s/::/\//g;
        my $ok_err= "Can't locate $class_path";
        die $msg if $msg !~  qr/^$ok_err/;
    }
    $@ = '';
}


1;
