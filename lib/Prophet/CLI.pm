package Prophet::CLI;
use Moose;
use MooseX::ClassAttribute;

use Prophet;
use Prophet::Replica;
use Prophet::CLI::Command;
use Prophet::CLI::Dispatcher;
use Prophet::CLIContext;

use List::Util 'first';

has app_class => (
    is      => 'rw',
    isa     => 'ClassName',
    default => 'Prophet::App',
);

has record_class => (
    is      => 'rw',
    isa     => 'ClassName',
    lazy    => 1,
    default => 'Prophet::Record',
);

has app_handle => (
    is      => 'rw',
    isa     => 'Prophet::App',
    lazy    => 1,
    handles => [qw/handle resdb_handle config/],
    default => sub {
        return $_[0]->app_class->new;
    },
);


has context => (
    is => 'rw',
    isa => 'Prophet::CLIContext',
    lazy => 1,
    default => sub {
        return Prophet::CLIContext->new( app_handle => shift->app_handle);
    }

);

has interactive_shell => ( 
    is => 'rw',
    isa => 'Bool',
    default => sub { 0}
);


=head2 _record_cmd

handles the subcommand for a particular type

=cut

=head2 dispatcher -> Class

Returns the dispatcher used to dispatch command lines. You'll want to override
this in your subclass.

=cut

sub dispatcher { "Prophet::CLI::Dispatcher" }

=head2 _get_cmd_obj

Attempts to determine a command object based on aliases and the currently
set commands, arguments, and properties. Returns the class on success;
dies on failure.

This routine will use a C<CLI::Command::Shell> class if no arguments are
specified.

This routine will use a C<CLI::Command::NotFound> class as a last resort, so
failure should occur rarely if ever.

=cut

sub _get_cmd_obj {
    my $self = shift;

    my $command = join ' ', @{ $self->context->primary_commands };

    # yeah this kind of sucks but there's no sane way to tell 
    my $class;
    my %dispatcher_args = (
        cli            => $self,
        context        => $self->context,
        got_command    => sub { $class = shift },
        dispatching_on => $self->context->primary_commands,
    );

    $self->dispatcher->run($command, %dispatcher_args);

    die "I don't know how to parse '$command'. Are you sure that's a valid command?" unless $class;

    my %constructor_args = (
        cli      => $self,
        context  => $self->context,
        commands => $self->context->primary_commands,
        type     => $self->context->type,
    );

    # undef causes type constraint violations
    for my $key (keys %constructor_args) {
        delete $constructor_args{$key}
            if !defined($constructor_args{$key});
    }

    $constructor_args{uuid} = $self->context->uuid
        if $self->context->has_uuid;

    return $class->new(%constructor_args);
}

sub _try_to_load_cmd_class {
    my $self = shift;
    my $class = shift;
    Prophet::App->try_to_require($class);
    return $class if $class->isa('Prophet::CLI::Command');

    warn "Invalid class $class - not a subclass of Prophet::CLI::Command."
        if $class !~ /::$/ # don't warn about "Prophet::CLI::Command::" (which happens on "./bin/sd")
        && Prophet::App->already_required($class);

    return undef;
}


=head2 run_one_command

Runs a command specified by commandline arguments given in ARGV. To use in
a commandline front-end, create a L<Prophet::CLI> object and pass in
your main app class as app_class, then run this routine.

Example:

 my $cli = Prophet::CLI->new({ app_class => 'App::SD' });
$cli->run_one_command;

=cut

sub run_one_command {
    my $self = shift;
     #  really, we shouldn't be doing this stuff from the command dispatcher
     $self->context(Prophet::CLIContext->new( app_handle => $self->app_handle)); 
	

    $self->context->parse_args();
    $self->context->set_type_and_uuid();
    if ( my $cmd_obj = $self->_get_cmd_obj() ) {
        $cmd_obj->run();
    }
}

=head2 invoke [outhandle], ARGV

Run the given command. If outhandle is true, select that as the file handle
for the duration of the command.

=cut

sub invoke {
    my ($self, $output, @args) = @_;
    my $ofh;

    local *ARGV = \@args;
    $ofh = select $output if $output;
    my $ret = eval {
        local $SIG{__DIE__} = 'DEFAULT';
        $self->run_one_command
    };
    warn $@ if $@;
    select $ofh if $ofh;
    return $ret;
}


__PACKAGE__->meta->make_immutable;
no Moose;

1;

