use warnings;
use strict;

package Prophet::Config;

use Path::Class;

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

my $singleton;
sub new {
    my $class = shift;
    return $singleton if $singleton;

    my $self = $singleton = bless {}, $class;
    $self->load_config_files;
    return $self;
}

=head2 prophet_config_file

The file which controls configuration for all Prophet apps. C<$HOME/.prophetc>.

=cut

sub prophet_config_file { dir($ENV{HOME}, ".prophetrc") }

=head2 app_config_file

The file which controls configuration for this application.
C<$PROPHET_REPO/prophetrc>.

=cut

sub app_config_file { dir($ENV{PROPHET_REPO}, "prophetrc") }

=head2 load_config_files [files]

Loads the given config files. If no files are passed in, it will use the
default of L</prophet_config_file> and L</app_config_file>.

=cut

sub load_config_files {
    my $self = shift;
    my @config = @_;
    @config = ($self->prophet_config_file, $self->app_config_file) if !@config;

    for my $file (@config) {
        $self->load_config_file($file);
    }
}

=head2 load_config_file file

Loads the given config file.

=cut

sub load_config_file {
    my $self = shift;
    my $file = shift;

    for my $line ($file->slurp) {
        s/\#.*//; # strip comments
        if ($line =~ /^([^:]+):\s*(.*)$/) {
            $self->{$1} = $2;
        }
    }
}

=head2 get

Gets a specific config setting.

=cut

sub get {
    my $self = shift;
    my $key  = shift;

    return $self->{$key};
}

=head2 set

Sets a specific config setting.

=cut

sub set {
    my $self  = shift;
    my $key   = shift;
    my $value = shift;

    return $self->{$key} = $value;
}
1;

