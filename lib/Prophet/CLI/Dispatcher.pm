package Prophet::CLI::Dispatcher;
use Path::Dispatcher::Declarative -base;
use Moose;
with 'Prophet::CLI::Parameters';

on [ ['create', 'new'] ]         => command("Create");
on [ ['show', 'display'] ]       => command("Show");
on [ ['update', 'edit'] ]        => command("Update");
on [ ['delete', 'del', 'rm'] ]   => command("Delete");
on [ ['search', 'list', 'ls' ] ] => command("Search");

on merge   => command("Merge");
on pull    => command("Pull");
on publish => command("Publish");
on server  => command("Server");
on config  => command("Config");
on log     => command("Log");
on shell   => command("Shell");

on export => sub {
    my $self = shift;
    $self->cli->handle->export_to(path => $self->context->arg('path'));
};

on push => sub {
    my $self = shift;

    die "Please specify a --to.\n" if !$self->context->has_arg('to');

    $self->context->set_arg(from => $self->cli->app_handle->default_replica_type.":file://".$self->cli->handle->fs_root);
    $self->context->set_arg(db_uuid => $self->cli->handle->db_uuid);
    run('merge', $self, @_);
};

on history => sub {
    my $self = shift;

    $self->context->require_uuid;
    my $record = $self->context->_load_record;
    $self->record($record);
    print $record->history_as_string;
};

sub command {
    my $name = shift;

    return sub {
        my $self = shift;
        my $class = $self->class_name($name);
        $class->new(cli => $self->cli)->run;
    };
}

sub class_name {
    my $command = shift;
    return "Prophet::CLI::Command::$command";
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;

