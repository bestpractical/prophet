package Prophet::Config;
use Any::Moose;
use File::Spec;
use Prophet::Util;
extends 'Config::GitLike';

has app_handle => (
    is => 'ro',
    weak_ref => 1,
    isa => 'Prophet::App',
    required => 1
);

# reload config after setting values
after set => sub  {
    my $self = shift;

    $self->load;
};

# per-replica config filename
override dir_file => sub { 'config' };

# Override the replica config file with the PROPHET_APP_CONFIG
# env var if it's set. Also, don't walk up the given path if no replica
# config is found.
override load_dirs => sub {
    my $self = shift;

    $self->load_file( $self->replica_config_file )
        if -f $self->replica_config_file;
};

# If PROPHET_APP_CONFIG is set, don't load anything else
override user_file => sub {
    my $self = shift;

    return exists $ENV{PROPHET_APP_CONFIG} ? '' : $self->SUPER::user_file(@_);
};

override global_file => sub {
    my $self = shift;

    return exists $ENV{PROPHET_APP_CONFIG} ? '' : $self->SUPER::global_file(@_);
};

# grab all values in the 'alias' section and strip away the section name
sub aliases {
    my $self = shift;

    my %aliases = $self->get_regexp( key => '^alias\.' );

    my %new_aliases = map {
        my $alias = $_;
        $alias =~ s/^alias\.//;
        ( $alias => $aliases{$_} );
    } keys %aliases;

    return wantarray ? %new_aliases : \%new_aliases;
}

# grab all values in the 'source' section and strip away the section name
sub sources {
    my $self = shift;

    my %sources = $self->get_regexp( key => '^source\.' );

    my %new_sources = map {
        my $source = $_;
        $source =~ s/^source\.//;
        ( $source => $sources{$_} );
    } keys %sources;

    return wantarray ? %new_sources : \%new_sources;
}

sub replica_config_file {
    my $self = shift;

    return exists $ENV{PROPHET_APP_CONFIG} ? $ENV{PROPHET_APP_CONFIG}
                : File::Spec->catfile(
                    $self->app_handle->handle->fs_root, $self->dir_file
    );
}

# friendly replica names go in the [display] section
sub display_name_for_uuid {
    my $self = shift;
    my $uuid = shift;

    my $friendly = $self->get( key => "display.$uuid" );
    return defined($friendly) ? $friendly : $uuid;
}

__PACKAGE__->meta->make_immutable;
no Any::Moose;

1;

__END__

=head1 NAME

Prophet::Config

=head1 SYNOPSIS

From, for example, a class that inherits from Prophet::App:

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
    );


=head1 DESCRIPTION

This class represents the configuration of Prophet and the application built on
top of it. It's just an instance of L<Config::GitLike|Config::GitLike> with
a few small customizations and additions.

=head1 METHODS

=head2 new( confname => 'prophetrc', app_handle => $instance_of_prophet_app )

Initialize the configuration. Does NOT load the config for you! You need to
call L<load|Config::GitLike/"load"> for that. The configuration will also
load automatically the first time your prophet application tries to
L<get|Config::GitLike/"get"> a config variable.

Both constructor arguments are required.

=head2 replica_config_file

The replica-specific configuration file, or the configuration file given
by C<PROPHET_APP_CONFIG> if that environmental variable is set.

=head2 aliases

A convenience method that gets you a hash (or a hashref, depending on context)
of all currently defined aliases. (Basically, every entry in the 'alias'
section of the config file.)

=head2 sources

A convenience method that gets you a hash (or a hashref, depending on context)
of all currently defined source replicas, in the format { 'name' =>
{ url => 'URL', uuid => 'UUID } }. (Basically, every entry in the 'replica'
section of the config file.)

=head2 display_name_for_uuid UUID

Returns a "friendly" id for the given uuid.

TODO: regexp search for 'replica.(.*).UUID' and extract the section

=head1 CONFIG VARIABLES

The following config variables are currently used in various places in
Prophet:

<record-type>.summary-format
record.summary-format
user.email-address
alias.<alias>

=head1 SEE ALSO

Most of the useful methods for getting and setting configuration variables
actually come from L<Config::GitLike|Config::GitLike>. See that module's
documentation for details.
