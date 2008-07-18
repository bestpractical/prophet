package Prophet::App;
use Moose;
use Path::Class;

has handle => (
    is      => 'rw',
    isa     => 'Prophet::Replica',
    lazy    => 1,
    default => sub {
        my $self = shift;
        my $root = $ENV{'PROPHET_REPO'} || dir($ENV{'HOME'}, '.prophet');
        my $type = $self->default_replica_type;
        return Prophet::Replica->new({ url => $type.':file://' . $root });
    },
);

has resdb_handle => (
    is      => 'rw',
    isa     => 'Prophet::Replica',
    lazy    => 1,
    default => sub {
        my $self = shift;
        return $self->handle->resolution_db_handle
            if $self->handle->resolution_db_handle;
        my $root = ($ENV{'PROPHET_REPO'} || dir($ENV{'HOME'}, '.prophet')) . "_res";
        my $type = $self->default_replica_type;
        return Prophet::Replica->new({ url => $type.':file://' . $root });
    },
);

has config => (
    is      => 'rw',
    isa     => 'Prophet::Config',
    default => sub {
        my $self = shift;
        Prophet::Config->require;
        return Prophet::Config->new(app_handle => $self);
    },
);

use constant DEFAULT_REPLICA_TYPE => 'prophet';

=head1 NAME

Prophet::App

=cut

sub BUILD {
    my $self = shift;
    $self->_load_replica_types();
}

sub _load_replica_types {
    my $self = shift;
    my $replica_class = blessed($self)."::Replica";
    my $except = $replica_class."::(.*)::";
    Module::Pluggable->import( search_path => $replica_class, sub_name => 'app_replica_types', require => 0, except => qr/$except/);
    for my $package ( $self->app_replica_types) {
        $package->require;
        next unless $package->can('scheme');
        Prophet::Replica->register_replica_scheme(scheme => $package->scheme, class => $package) 
    }
}

sub default_replica_type {
    my $self = shift;
    return $ENV{'PROPHET_REPLICA_TYPE'} || DEFAULT_REPLICA_TYPE;
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

=head2 config

Returns the L<Prophet::Config> instance for the running application

=cut


__PACKAGE__->meta->make_immutable;
no Moose;

1;
