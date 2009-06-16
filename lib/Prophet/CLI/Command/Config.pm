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
    print "Config files:\n\n";
    for my $file (@files) {
        print "$file\n";
    }
    print "\nYour configuration:\n\n";
    $config->dump;
}

sub no_config_files {
    my $self = shift;
    return "No configuration files found. "
         . " Either create a file called
         '".$self->handle->app_handle->config->replica_config_file.
         "' or set the PROPHET_APP_CONFIG environment variable.\n\n";
}

__PACKAGE__->meta->make_immutable;
no Any::Moose;

1;

