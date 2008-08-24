package Prophet::CLI;
use Moose;
use MooseX::ClassAttribute;

use Prophet;
use Prophet::Replica;
use Prophet::CLI::Command;
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
    handles => [qw/has_arg set_arg arg delete_arg arg_hash prop_get set_prop prop_set prop_names props/],
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

our %CMD_MAP = (
    ls      => 'search',
    new     => 'create',
    edit    => 'update',
    rm      => 'delete',
    del     => 'delete',
    list    => 'search',
    display => 'show',
);

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

    my $aliases  = $self->config->aliases;
    my $tmp      = $self->context->primary_commands;
    if (@$tmp && $aliases->{$tmp->[0]}) {
        @ARGV = split ' ', $aliases->{$tmp->[0]};
        return $self->run_one_command;
    }
    my @commands = map { exists $CMD_MAP{$_} ? $CMD_MAP{$_} : $_ } @{ $tmp };

    # allow overriding of default command. "./prophet" starts a prophet shell
    @commands = $self->_default_command
        if @commands == 0;

    my @possible_classes;

    my @to_try = @commands;

    while (@to_try) {

        # App::SD::CLI::Command::Ticket::Comment::List
        my $cmd = $self->app_class . "::CLI::Command::" . join('::', map { ucfirst lc $_ } @to_try);

        push @possible_classes, $cmd;
        shift @to_try;
        # throw away that top-level "Ticket" option
    }

    my @extreme_fallback_commands;

    # App::SD::CLI::Command::List
    # Prophet::CLI::Command::List
    for my $main ($self->app_class, 'Prophet') {
        push @extreme_fallback_commands, $main . "::CLI::Command::" . ucfirst(lc $commands[-1]);
    }

    # App::SD::CLI::Command::NotFound
    # Prophet::CLI::Command::NotFound
    for my $main ($self->app_class, 'Prophet') {
        push @extreme_fallback_commands, $main . "::CLI::Command::NotFound";
    }

    my $class = first { $self->_try_to_load_cmd_class($_) }
                @possible_classes, @extreme_fallback_commands;

    die "I don't know how to parse '" . join( " ", @{ $self->context->primary_commands } ) . "'. Are you sure that's a valid command?" unless ($class);

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

=head2 _default_command

Returns the "default" command for use when no arguments were specified on the
command line. In Prophet, it's "shell" but your subclass can change that.

=cut

sub _default_command { "shell" }

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

