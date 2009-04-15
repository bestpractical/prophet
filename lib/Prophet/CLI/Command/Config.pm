package Prophet::CLI::Command::Config;
use Any::Moose;
extends 'Prophet::CLI::Command';

sub run {
    my $self = shift;

    my $config = $self->config;

    print "Configuration:\n\n";
    my @files =@{$config->config_files};
    if (!scalar @files) {
        print $self->no_config_files;
        return;
    }
    for my $file (@files) {
        print "Config files:\n\n";
        print "$file\n";
    }
    print "\nYour configuration:\n\n";
    for my $item ( $config->list ) {
        if ( $item eq '_aliases' ) {
            if ( my $aliases = $config->aliases ) {
                for my $key ( keys %$aliases ) {
                    print "alias $key = $aliases->{$key}\n";
                }
            }
        }
        elsif ( $item eq '_sources' ) {
            if ( my $sources = $config->sources ) {
                for my $key ( keys %$sources ) {
                    print "source $key = $sources->{$key}\n";
                }
            }
        }
        else {
            print $item . " = " . $config->get($item) . "\n";
        }
    }
}

sub no_config_files {
    my $self = shift;
    return "No configuration files found. "
         . " Either create a file called 'config' inside of "
         . $self->handle->fs_root
         . " or set the PROPHET_APP_CONFIG environment variable.\n\n";
}

__PACKAGE__->meta->make_immutable;
no Any::Moose;

1;

