package Prophet::CLI::Command::Config;
use Moose;
extends 'Prophet::CLI::Command';

sub run {

    my $self = shift;

    my $config = $self->config;
   
    print "Configuration:\n\n";
    my @files =@{$config->config_files};
    if (!scalar @files) {
        print "No configuration files found. ".
            " Either create a file called 'prophetrc' inside of ". $self->handle->fs_root ." or set the PROPHET_APP_CONFIG environement variable.\n\n";
        return;
    }
    for my $file (@files) {
        print "Config files:\n\n";
            print "$file\n";    
    }
    print "\nYour configuration:\n\n";
    for my $item ($config->list) {
        print $item ." = ".$config->get($item)."\n";
    }

}

__PACKAGE__->meta->make_immutable;
no Moose;

1;

