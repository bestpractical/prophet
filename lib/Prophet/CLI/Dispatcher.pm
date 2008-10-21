package Prophet::CLI::Dispatcher;
use Path::Dispatcher::Declarative -base;
use Moose;
with 'Prophet::CLI::Parameters';

# "ticket display $ID" -> "ticket display --id=$ID"
on qr{^ (.*) \s+ ( \d+ | [A-Z0-9]{36} ) $ }x => sub {
    my $self = shift;
    $self->context->set_arg(id => $2);
    redispatch($1, $self, @_);
};

on [ ['create', 'new'] ]         => run("Create");
on [ ['show', 'display'] ]       => run("Show");
on [ ['update', 'edit'] ]        => run("Update");
on [ ['delete', 'del', 'rm'] ]   => run("Delete");
on [ ['search', 'list', 'ls' ] ] => run("Search");

on merge   => run("Merge");
on pull    => run("Pull");
on publish => run("Publish");
on server  => run("Server");
on config  => run("Config");
on log     => run("Log");
on shell   => run("Shell");

on export => sub {
    my $self = shift;
    $self->cli->handle->export_to(path => $self->context->arg('path'));
};

on push => sub {
    my $self = shift;

    die "Please specify a --to.\n" if !$self->context->has_arg('to');

    $self->context->set_arg(from => $self->cli->app_handle->default_replica_type.":file://".$self->cli->handle->fs_root);
    $self->context->set_arg(db_uuid => $self->cli->handle->db_uuid);
    redispatch('merge', $self, @_);
};

on history => sub {
    my $self = shift;

    $self->context->require_uuid;
    my $record = $self->context->_load_record;
    $self->record($record);
    print $record->history_as_string;
};

sub run {
    my $name = shift;

    return sub {
        my $self = shift;
        my $class = $self->class_name($name);
        Prophet::App->require($class);

        my %constructor_args = (
            cli      => $self->cli,
            context  => $self->context,
            commands => $self->context->primary_commands,
            type     => $self->context->type,
            uuid     => $self->context->uuid,
        );

    # undef causes type constraint violations
    for my $key (keys %constructor_args) {
        delete $constructor_args{$key}
            if !defined($constructor_args{$key});
    }
        $class->new(%constructor_args)->run;
    };
}

sub class_name {
    my $self = shift;
    my $command = shift;
    return "Prophet::CLI::Command::$command";
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;

