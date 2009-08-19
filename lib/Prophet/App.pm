package Prophet::App;
use Any::Moose;
use File::Spec ();
use Prophet::Config;
use Prophet::UUIDGenerator;
use Params::Validate qw/validate validate_pos/;

has handle => (
    is      => 'rw',
    isa     => 'Prophet::Replica',
    lazy    => 1,
    default => sub {
        my $self = shift;

        if ( defined $self->local_replica_url
                && $self->local_replica_url !~ /^[\w\+]{2,}\:/ ) {
# the reason why we need {2,} is to not match name on windows, e.g. C:\foo
            my $path = $self->local_replica_url;
            $path = File::Spec->rel2abs(glob($path)) unless File::Spec->file_name_is_absolute($path);
            $self->local_replica_url("file://$path");
        }

        return Prophet::Replica->get_handle( url =>  $self->local_replica_url, app_handle => $self, );
    },
);

has config => (
    is      => 'rw',
    isa     => 'Prophet::Config',
    default => sub {
        my $self = shift;
        return Prophet::Config->new(
            app_handle => $self,
            confname => 'prophetrc',
        );
    },
    documentation => "This is the config instance for the running application",
);



use constant DEFAULT_REPLICA_TYPE => 'prophet';

=head1 NAME

Prophet::App

=head1 SYNOPSIS

=head1 METHODS

=head2 BUILD

=cut

=head2 default_replica_type

Returns a string of the the default replica type for this application.

=cut

sub default_replica_type {
    my $self = shift;
    return $ENV{'PROPHET_REPLICA_TYPE'} || DEFAULT_REPLICA_TYPE;
}


=head2 local_replica_url

Returns the URL of the current local replica. If no URL has been
provided (usually via C<$ENV{PROPHET_REPO}>), returns undef.

=cut

sub local_replica_url {
	my $self = shift;
	if (@_) {
		$ENV{'PROPHET_REPO'} = shift;
	}

	return $ENV{'PROPHET_REPO'} || undef;
}

=head2 require

=cut

sub require {
    my $self = shift;
    my $class = shift;
    $self->_require(module => $class);
}

=head2 try_to_require

=cut

sub try_to_require {
    my $self = shift;
    my $class = shift;
    $self->_require(module => $class, quiet => 1);
}

=head2 _require

=cut

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

    return 0 if $class =~ /::$/;    # malformed class

    my $path =  join('/', split(/::/,$class)).".pm";
    return ( $INC{$path} ? 1 : 0);
}

sub set_db_defaults {
    my $self = shift;
    my $settings = $self->database_settings;
    for my $name ( keys %$settings ) {
        my ($uuid, @metadata) = @{$settings->{$name}};

        my $s = $self->setting(
            label   => $name,
            uuid    => $uuid,
            default => \@metadata,
        );

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


=head3 log $MSG

Logs the given message to C<STDERR> (but only if the C<PROPHET_DEBUG>
environmental variable is set).

=cut

sub log_debug {
    my $self = shift;
    return unless ($ENV{'PROPHET_DEBUG'});
    $self->log(@_);
}

sub log {
    my $self = shift;
    my ($msg) = validate_pos(@_, 1);
    print STDERR $msg."\n";# if ($ENV{'PROPHET_DEBUG'});
}

=head2 log_fatal $MSG

Logs the given message and dies with a stack trace.

=cut

sub log_fatal {
    my $self = shift;

    # always skip this fatal_error function when generating a stack trace
    local $Carp::CarpLevel = $Carp::CarpLevel + 1;

    $self->log(@_);
    Carp::confess(@_);
}


sub current_user_email {
    my $self = shift;
    return $self->config->get( key => 'user.email-address' ) || $ENV{'PROPHET_EMAIL'} || $ENV{'EMAIL'};

}

=head2 display_name_for_replica UUID

Returns a "friendly" id for the replica with the given uuid. UUIDs are for
computers, friendly names are for people. If no name is found, the friendly
name is just the UUID.

=cut

# friendly names are replica subsections in the config file
sub display_name_for_replica {
    my $self = shift;
    my $uuid = shift;

    my %possibilities = $self->config->get_regexp( key => '^replica\..*\.uuid$' );
    # form a hash of uuid -> name
    my %sources_by_uuid = map {
        my $uuid = $possibilities{$_};
        $_ =~ /^replica\.(.*)\.uuid$/;
        my $name = $1;
        ( $uuid => $name );
    } keys %possibilities;
    return exists $sources_by_uuid{$uuid} ? $sources_by_uuid{$uuid} : $uuid;
}

__PACKAGE__->meta->make_immutable;
no Any::Moose;

1;
