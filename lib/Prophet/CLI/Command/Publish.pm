package Prophet::CLI::Command::Publish;
use Moose;
extends 'Prophet::CLI::Command::Export';
with 'Prophet::CLI::PublishCommand';
with 'Prophet::CLI::CollectionCommand';

before run => sub {
    my $self = shift;
    die "Please specify a --to.\n" unless $self->has_arg('to');

    # set the temp directory where we will do all of our work, which will be
    # published via rsync
    $self->set_arg(path => $self->tempdir);
};

around run => sub {
    my $orig = shift;
    my $self = shift;

    # if the user specifies nothing, then publish the replica
    $self->set_arg('replica' => 1)
        if !$self->has_arg('html');

    # if we have the html argument, populate the tempdir with rendered templates
    if ($self->has_arg('html')) {
        $self->render_templates_into($self->arg('path'));
    }

    # otherwise, do the normal prophet export this replica
    if ($self->has_arg('replica')) {
        $self->$orig(@_);
    }
};

# the tempdir is populated, now publish it
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

# helper methods for rendering templates
sub render_templates_into {
    my $self = shift;
    my $dir  = shift;

    require Prophet::Server::View;
    Template::Declare->init(roots => ['Prophet::Server::View']);

    # allow user to specify a specific type to render
    my @types = $self->type || $self->types_to_render;

    for my $type (@types) {
        my $subdir = $dir->subdir($type);
        $subdir->mkpath;

        my $records = $self->get_collection_object(type => $type);
        $records->matching(sub { 1 });

        my $fh = $subdir->file('index.html')->openw;
        print { $fh } Template::Declare->show('record_table' => $records);
        close $fh;

        for my $record ($records->items) {
            my $fh = $subdir->file($record->uuid . '.html')->openw;
            print { $fh } Template::Declare->show('record' => $record);
        }
    }
}

sub should_skip_type {
    my $self = shift;
    my $type = shift;

    # should we skip all _private types?
    return 1 if $type eq '_merge_tickets';

    return 0;
}

sub types_to_render {
    my $self = shift;

    return grep { !$self->should_skip_type($_) }
           @{ $self->app_handle->handle->list_types };
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;

