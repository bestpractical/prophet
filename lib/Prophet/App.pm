package Prophet::App;
use Moose;
use Path::Class;
use Prophet::Config;
use Params::Validate qw/validate/;

has handle => (
    is      => 'rw',
    isa     => 'Prophet::Replica',
    lazy    => 1,
    default => sub {
        my $self = shift;
        my $root = $ENV{'PROPHET_REPO'} || dir($ENV{'HOME'}, '.prophet');
        my $type = $self->default_replica_type;
        return Prophet::Replica->new({ url => $type.':file://' . $root, app_handle => $self, after_initialize => sub { $self->set_database_defaults} });
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
        return Prophet::Config->new(app_handle => $self);
    },
    documentation => "This is the config instance for the running application",
);

use constant DEFAULT_REPLICA_TYPE => 'prophet';

=head1 NAME

Prophet::App

=cut

sub default_replica_type {
    my $self = shift;
    return $ENV{'PROPHET_REPLICA_TYPE'} || DEFAULT_REPLICA_TYPE;
}

sub require {
    my $self = shift;
    my $class = shift;
    $self->_require(module => $class);
}

sub try_to_require {
    my $self = shift;
    my $class = shift;
    $self->_require(module => $class, quiet => 1);
}


sub _require {
    my $self = shift;
    my %args = ( module => undef, quiet => undef, @_);
    my $class = $args{'module'};

    # Quick hack to silence warnings.
    # Maybe some dependencies were lost.
    unless ($class) {
        warn sprintf("no class was given at %s line %d\n", (caller)[1,2]);
        return 0;
    }

    return 1 if $self->already_required($class);

    # .pm might already be there in a weird interaction in Module::Pluggable
    my $file = $class;
    $file .= ".pm"
        unless $file =~ /\.pm$/;

    $file =~ s/::/\//g;

    my $retval = eval {
        local $SIG{__DIE__} = 'DEFAULT';
        CORE::require "$file"
    };

    my $error = $@;
    if (my $message = $error) {
        $message =~ s/ at .*?\n$//;
        if ($args{'quiet'} and $message =~ /^Can't locate \Q$file\E/) {
            return 0;
        }
        elsif ( $error !~ /^Can't locate $file/) {
            die $error;
        } else {
            warn sprintf("$message at %s line %d\n", (caller(1))[1,2]);
            return 0;
        }
    }

    return 1;
}

=head2 already_required class

Helper function to test whether a given class has already been require'd.

=cut

sub already_required {
    my ($self, $class) = @_;
    my $path =  join('/', split(/::/,$class)).".pm";
    return ( $INC{$path} ? 1 : 0);
}


sub set_database_defaults {
    my $self = shift;
    my $settings = $self->database_settings;
    for my $name ( keys %$settings ) {
        my @metadata = @{$settings->{$name}};
        my $s = $self->setting(  label => $name, uuid => (shift @metadata), default => [@metadata]);
        $s->initialize;
    }
}

sub setting {
    my $self = shift;
    my %args = validate( @_, { uuid => 0, default => 0, label => 0 } );
    require Prophet::DatabaseSetting;

    my  ($uuid, $default);

    if ( $args{uuid} ) {
        $uuid = $args{'uuid'};
        $default = $args{'default'};
    } elsif ( $args{'label'} ) {
        ($uuid, $default) = @{ $self->database_settings->{ $args{'label'} }};
    }
    return Prophet::DatabaseSetting->new(
        handle  => $self->handle,
        uuid    => $uuid,
        default => $default,
        label   => $args{label}
    );

}

sub database_settings {} # XXX wants a better name

__PACKAGE__->meta->make_immutable;
no Moose;

1;
