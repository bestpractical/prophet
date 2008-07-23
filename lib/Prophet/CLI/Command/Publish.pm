package Prophet::CLI::Command::Publish;
use Moose;
extends 'Prophet::CLI::Command::Export';
with 'Prophet::CLI::PublishCommand';

before run => sub {
    my $self = shift;
    die "Please specify a --to.\n" unless $self->has_arg('to');
};

before run => sub {
    my $self = shift;
    $self->set_arg(path => $self->tempdir);
};

after run => sub {
    my $self = shift;
    my $from = $self->arg('path');
    my $to   = $self->arg('to');

    $self->publish_dir(
        from => $from,
        to   => $to,
    );

    print "Publish complete.\n";
};

__PACKAGE__->meta->make_immutable;
no Moose;

1;

