package Prophet::CLI::PublishCommand;
use Any::Moose 'Role';

use File::Temp ();

sub tempdir { my $dir = File::Temp::tempdir(CLEANUP => ! $ENV{PROPHET_DEBUG} ); return $dir; }

sub publish_dir {
    my $self = shift;
    my %args = @_;


    $args{from} .= '/';

    my @args;
    push @args, '--verbose' if $self->context->has_arg('verbose');
    
    push @args, '--recursive', '--' , $args{from}, $args{to};

    my $rsync = $ENV{RSYNC} || "rsync";
    my $ret = system($rsync, @args);

    if ($ret == -1) {
        die "You must have 'rsync' installed to use this command.

If you have rsync but it's not in your path, set environment variable \$RSYNC to the absolute path of your rsync executable.\n";
    }

    return $ret;
}

no Any::Moose;

1;

