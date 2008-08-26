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
    push @args, '--verbose' if $self->context->has_arg('verbose');

    push @args, '--';

    push @args, dir($args{from})->children;

    push @args, $args{to};

    my $rsync = $ENV{RSYNC} || "rsync";
    my $ret = system($rsync, @args);

    if ($ret == -1) {
        die "You must have 'rsync' installed to use this command.

If you have rsync but it's not in your path, set environment variable \$RSYNC to the absolute path of your rsync executable.\n";
    }

    return $ret;
}

no Moose::Role;

1;

