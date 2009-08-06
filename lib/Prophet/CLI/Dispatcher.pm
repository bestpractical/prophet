package Prophet::CLI::Dispatcher;
use Path::Dispatcher::Declarative -base;
use Any::Moose;
extends 'Path::Dispatcher::Declarative', any_moose('Object');

require Prophet::CLIContext;

with 'Prophet::CLI::Parameters';

our @PREFIXES = qw(Prophet::CLI::Command);
sub add_command_prefix { unshift @PREFIXES, @_ }

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
on qr{log\s+([0-9LATEST.~]+)} => sub {
    my $self = shift;
    $self->context->set_arg(range => $1);
    run('log', $self);
};

under settings => sub {
    my $self = shift;
    on edit => sub {
        my $self = shift;
        $self->context->set_arg( 'edit' );
        run('settings', $self);
    };
    on show => sub {
        my $self = shift;
        $self->context->set_arg( 'show' );
        run('settings', $self);
    };
    on set => sub {
        my $self = shift;
        $self->context->set_arg( 'set' );
        run('settings', $self);
    };
};

on [ qr/^(update|edit|show|display|delete|del|rm|history)$/,
     qr/^$Prophet::CLIContext::ID_REGEX$/i ] => sub {
    my $self = shift;
    $self->context->set_id_from_primary_commands;
    run($1, $self, @_);
};

on [ [ 'update', 'edit' ] ]      => run_command("Update");
on [ [ 'show', 'display' ] ]     => run_command("Show");
on [ [ 'delete', 'del', 'rm' ] ] => run_command("Delete");
on history                       => run_command("History");

on [ ['create', 'new'] ]         => run_command("Create");
on [ ['search', 'list', 'ls' ] ] => run_command("Search");
on [ ['aliases', 'alias'] ]      => run_command('Aliases');

on version  => run_command("Version");
on init     => run_command("Init");
on clone    => run_command("Clone");
on merge    => run_command("Merge");
on mirror   => run_command('Mirror');
on pull     => run_command("Pull");
on publish  => run_command("Publish");
on server   => run_command("Server");
on config   => run_command("Config");
on settings => run_command("Settings");
on log      => run_command("Log");
on shell    => run_command("Shell");
on export   => run_command('Export');
on info     => run_command('Info');
on push     => run_command('Push');

on qr/^(alias(?:es)?|config)?\s+(.*)/ => sub {
    my ( $self ) = @_;
    my $cmd = $1;
    my $arg = $2;

    my $class = $cmd =~ /^alias/ ? 'Aliases' : 'Config';

    # Load command class so we can run
    # its arg-parsing sub (the syntax is complex)
    my @classes = $self->class_names($class);
    for my $class (@classes) {
        Prophet::App->try_to_require($class) or next;
        my $cmd_obj = $class->new(
            context => $self->context,
            cli     => $self->cli,
        );
        $cmd_obj->parse_cli_arg($cmd, $arg);
        return run( $cmd, $self, @_ );
    }

    # Something is wrong with the app layout...
    die "Could not find '$class' command class";
};

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

