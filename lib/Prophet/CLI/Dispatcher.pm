package Prophet::CLI::Dispatcher;
use Path::Dispatcher::Declarative -base;
use Any::Moose;

with 'Prophet::CLI::Parameters';

our @PREFIXES = qw(Prophet::CLI::Command);
sub add_command_prefix { unshift @PREFIXES, @_ }

# "ticket display $ID" -> "ticket display --id=$ID"
on qr{^ (.*) \s+ ( \d+ | [A-Z0-9]{36} ) $ }x => sub {
    my $self = shift;
    $self->context->set_arg(id => $2);
    run($1, $self, @_);
};

on '' => sub {
    my $self = shift;
    if ($self->context->has_arg('version')) { run_command("Version")->($self) }
    elsif( $self->context->has_arg('help') ){ run_command("Help")->($self) }
    else { next_rule }
};

# publish foo@bar.com:www/baz => publish --to foo@bar.com:www/baz
on qr{^(publish|push) (\S+)$} => sub {
    my $self = shift;
    $self->context->set_arg(to => $2);
    run($1, $self);
};

# clone http://fsck.com/~jesse/sd-bugs => clone --from http://fsck.com/~jesse/sd-bugs
on qr{^(clone|pull) (\S+)$} => sub {
    my $self = shift;
    $self->context->set_arg(from => $2);
    run($1, $self);
};

# log range => log --range range
on qr{log\s*([0-9LATEST.~]+)} => sub {
    my $self = shift;
    $self->context->set_arg(range => $1);
    run('log', $self);
};

on [ ['create', 'new'] ]         => run_command("Create");
on [ ['show', 'display'] ]       => run_command("Show");
on [ ['update', 'edit'] ]        => run_command("Update");
on [ ['delete', 'del', 'rm'] ]   => run_command("Delete");
on [ ['search', 'list', 'ls' ] ] => run_command("Search");

on version  => run_command("Version");
on init     => run_command("Init");
on clone    => run_command("Clone");
on merge    => run_command("Merge");
on pull     => run_command("Pull");
on publish  => run_command("Publish");
on server   => run_command("Server");
on config   => run_command("Config");
on settings => run_command("Settings");
on log      => run_command("Log");
on shell    => run_command("Shell");
on aliases  => run_command("Aliases");
on export => run_command('Export');

on push => sub {
    my $self = shift;

    die "Please specify a --to.\n" if !$self->context->has_arg('to');

    $self->context->set_arg(from => $self->cli->app_handle->default_replica_type.":file://".$self->cli->handle->fs_root);
    $self->context->set_arg(db_uuid => $self->cli->handle->db_uuid);
    run('merge', $self, @_);
};

on history => run_command('History');

sub run_command {
    my $name = shift;
    return sub {
        my $self = shift;
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

        my @classes = $self->class_names($name);
        for my $class (@classes) {
            Prophet::App->try_to_require($class) or next;
            $class->new(%constructor_args)->run;
            return;
        }

        die "Invalid command command class suffix '$name'";
    };
}

sub class_names {
    my $self = shift;
    my $command = shift;
    return map { $_."::".$command } @PREFIXES;

}

__PACKAGE__->meta->make_immutable;
no Any::Moose;

1;

