package Prophet::Config;
use Moose;
use MooseX::AttributeHelpers;
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
    metaclass => 'Collection::Hash',
    is        => 'rw',
    isa       => 'HashRef',
    lazy      => 0,
    default   => sub { shift->load_from_files },
    provides  => {
        get   => 'get',
        set   => 'set',
        keys  => 'list'
    },
);

#sub prophet_config_file { dir($ENV{HOME}, ".prophetrc") }
sub app_config_file { 
    my $self = shift;
    $ENV{'PROPHET_APP_CONFIG'} || file( $self->app_handle->handle->fs_root => "prophetrc" ) 

}

#my $singleton;
#around new => sub { return $singleton if $singleton; my $orig = shift; return $singleton = $orig->(@_); };

sub load_from_files {
    my $self = shift;
    my @config = @_;
    @config = grep { -f $_ } $self->app_config_file if !@config;
    #@config = grep { -f $_ } $self->prophet_config_file, $self->app_config_file if !@config;

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
            $config->{$1} = $2;
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

=head2 load_from_files [files]

Loads the given config files. If no files are passed in, it will use the
default of L</prophet_config_file> and L</app_config_file>.

=head2 load_from_file file

Loads the given config file.

=head2 get

Gets a specific config setting.

=head2 set

Sets a specific config setting.

=head2 list

List all configuration options

=cut

