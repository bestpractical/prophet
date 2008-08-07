package Prophet::CLI::PublishCommand;
use Moose::Role;

use Path::Class;
use File::Temp ();

sub tempdir { dir(File::Temp::tempdir(CLEANUP => 1)) }

sub publish_dir {
    my $self = shift;
    my %args = @_;

    my @args;
    push @args, '--recursive';
    push @args, '--verbose' if $self->has_arg('verbose');

    push @args, '--';

    push @args, dir($args{from})->children;

    push @args, $args{to};

    system("rsync", @args);
}

no Moose::Role;

1;

