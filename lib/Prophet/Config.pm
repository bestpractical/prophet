package Prophet::Config;
use Moose;
use MooseX::AttributeHelpers;
use Path::Class;

has config => (
    metaclass => 'Collection::Hash',
    is        => 'rw',
    isa       => 'HashRef',
    lazy      => 1,
    default   => sub { shift->load_config_files },
    provides  => {
        get   => 'get',
        set   => 'set',
    },
);

sub prophet_config_file { dir($ENV{HOME}, ".prophetrc") }
sub app_config_file { dir($ENV{PROPHET_REPO}, "prophetrc") }

my $singleton;
around new => sub {
    return $singleton if $singleton;
    my $orig = shift;
    return $singleton = $orig->(@_);
};

sub load_config_files {
    my $self = shift;
    my @config = @_;
    @config = grep { -f $_ } $self->prophet_config_file, $self->app_config_file
        if !@config;

    my $config = {};

    for my $file (@config) {
        $self->load_config_file($file, $config);
    }

    return $config;
}

sub load_config_file {
    my $self   = shift;
    my $file   = shift;
    my $config = shift || {};

    for my $line ($file->slurp) {
        s/\#.*//; # strip comments
        if ($line =~ /^([^:]+):\s*(.*)$/) {
            $config->{$1} = $2;
        }
    }
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;

__END__

=head1 NAME

Prophet::Config

=head1 SYNOPSIS

    In ~/.prophetrc:

        prefer_luids: 1

=head1 DESCRIPTION

This class represents configuration of Prophet and the application built on top
of it.

=head1 METHODS

=head2 new

Takes no arguments. Automatically loads the config for you. This is actually
a singleton so multiple calls to new get the same config.

=cut

=head2 prophet_config_file

The file which controls configuration for all Prophet apps. C<$HOME/.prophetc>.

=head2 app_config_file

The file which controls configuration for this application.
C<$PROPHET_REPO/prophetrc>.

=head2 load_config_files [files]

Loads the given config files. If no files are passed in, it will use the
default of L</prophet_config_file> and L</app_config_file>.

=head2 load_config_file file

Loads the given config file.

=head2 get

Gets a specific config setting.

=head2 set

Sets a specific config setting.

=cut

