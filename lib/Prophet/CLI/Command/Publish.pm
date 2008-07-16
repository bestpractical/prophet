package Prophet::CLI::Command::Publish;
use Moose;
extends 'Prophet::CLI::Command::Export';

use File::Temp 'tempdir';
use File::Rsync;

before run => sub {
    my $self = shift;
    die "Please specify a --to.\n" unless $self->has_arg('to');
};

before run => sub {
    my $self = shift;
    my $dir = tempdir(CLEANUP => 1);
    $self->set_arg(path => $dir);
};

after run => sub {
    my $self = shift;
    my $from = $self->arg('path');
    my $to   = $self->arg('to');

    my $rsync = File::Rsync->new;
    $rsync->exec({
        src       => $from,
        dst       => $to,
        recursive => 1,
    });

    warn $_ for $rsync->err;
    print $_ for $rsync->out;
};

__PACKAGE__->meta->make_immutable;
no Moose;

1;

