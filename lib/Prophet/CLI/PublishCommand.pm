package Prophet::CLI::PublishCommand;
use Moose::Role;

use Path::Class;
use File::Temp ();
use File::Rsync;

sub tempdir {
    my $self = shift;
    my $tmp = File::Temp::tempdir(CLEANUP => 1);
    my $uuid = $self->app_handle->handle->db_uuid;

    my $dir = dir($tmp, $uuid);
    $dir->mkpath;

    return $dir;
}

sub publish_dir {
    my $self = shift;
    my %args = @_;

    my $rsync = File::Rsync->new;
    $rsync->exec({
        src       => $args{from},
        dst       => $args{to},
        recursive => 1,
        verbose   => $self->has_arg('verbose'),
    });

    warn $_ for $rsync->err;
    print $_ for $rsync->out;

    return $rsync;
}

no Moose::Role;

1;

