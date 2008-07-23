package Prophet::CLI::Command::Html;
use Moose;
extends 'Prophet::CLI::Command';
with 'Prophet::CLI::PublishCommand';
with 'Prophet::CLI::CollectionCommand';

use Path::Class;
use Prophet::Server::View;

sub run {
    my $self = shift;

    die "Please specify a --to.\n" unless $self->has_arg('to');
    my $from = $self->tempdir;

    Template::Declare->init(roots => ['Prophet::Server::View']);
    $self->render_templates_into($from);

    $self->publish_dir(
        from => $from,
        to   => $self->arg('to'),
    );

    print "Publish complete.\n";
}

sub render_templates_into {
    my $self = shift;
    my $dir  = shift;

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

