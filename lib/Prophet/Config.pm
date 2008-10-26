package Prophet::Config;
use Moose;
use MooseX::AttributeHelpers;
use File::Spec;
use Path::Class;

has app_handle => (
    is => 'ro',
    weak_ref => 1,
    isa => 'Prophet::App',
    required => 0
);

has config_files => ( 
    is => 'rw',
    isa => 'ArrayRef' ,
    default =>sub  {[]}
);

has config => (
    metaclass   => 'Collection::Hash',
    is          => 'rw',
    isa         => 'HashRef',
    lazy        => 0,
    default     => sub {shift->load_from_files;},
    provides    => {
        get     => 'get',
        set     => 'set',
        keys    => 'list',
    },
);

sub aliases {
    return $_[0]->config->{_aliases};
}

sub app_config_file {
    my $self = shift;

    return $self->file_if_exists($ENV{'PROPHET_APP_CONFIG'})
        || $self->file_if_exists(
            File::Spec->catfile(
                $self->app_handle->handle->fs_root => 'prophetrc' ))
        || $self->file_if_exists(
            File::Spec->catfile( $ENV{'HOME'} => '.prophetrc' ));
}

#my $singleton;
#around new => sub { return $singleton if $singleton; my $orig = shift; return $singleton = $orig->(@_); };

sub load_from_files {
    my $self = shift;
    my @config = @_;
    @config = grep { -f $_ } $self->app_config_file if !@config;
    my $config = {};

    for my $file (@config) {
        $self->load_from_file(file($file), $config);
        push @{$self->config_files}, $file;
    }

    return $config;
}

sub load_from_file {
    my $self   = shift;
    my $file   = shift;
    my $config = shift || {};

    for my $line ($file->slurp) {
        $line =~ s/\#.*$//; # strip comments
        next unless ($line =~ /^([^:]+?)\s*=\s*(.*)$/);
        my $key = $1;
        my $val = $2;
        if ($key =~ m!alias\s+(.+)!) {
            $config->{_aliases}->{$1} = $val;
        } else { 
            $config->{$key} = $val;
        }
    }
}

sub display_name_for_uuid {
    my $self = shift;
    my $uuid = shift;

    my $friendly = $self->get("display_$uuid");
    return defined($friendly) ? $friendly : $uuid;
}

=head2 file_if_exists FILENAME

Returns the given filename if it exists on the filesystem, and an
empty string otherwise.

=cut

sub file_if_exists {
    my $self = shift;
    my $file = shift || ''; # quiet warnings

    return (-e $file) ? $file : '';
}

__PACKAGE__->meta->make_immutable;
no Moose;

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
(the $PROPHET_APP_CONFIG environmental variable, C<$PROPHET_REPO/prophetrc>,
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

