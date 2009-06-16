package Prophet::Config;
use Any::Moose;
use File::Spec;
use Prophet::Util;
extends 'Config::GitLike';

has app_handle => (
    is => 'ro',
    weak_ref => 1,
    isa => 'Prophet::App',
    required => 0
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

    In the Prophet config file (see L</app_config_file>):

      prefer_luids: 1
      summary_format_ticket = %4s },$luid | %-11.11s,status | %-70.70s,summary

=head1 DESCRIPTION

This class represents the configuration of Prophet and the application built on
top of it.

=head1 METHODS

=head2 new

Takes no arguments. Automatically loads the config for you.

=cut

=head2 app_config_file

The file which controls configuration for this application
(the $PROPHET_APP_CONFIG environmental variable, C<$PROPHET_REPO/config>,
or C<$HOME/.prophetrc>, in that order).

=head2 load_from_files [files]

Loads the given config files. If no files are passed in, it will use the
default of L</app_config_file>.

=head2 load_from_file file

Loads the given config file.

=head2 get

Gets a specific config setting.

=head2 set

Sets a specific config setting.

=head2 list

Lists all configuration options.

=head2 display_name_for_uuid UUID

Returns a "friendly" id for the given uuid.

=cut

