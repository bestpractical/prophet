package Prophet::CLI;
use Moose;
use MooseX::ClassAttribute;

use Prophet;
use Prophet::Record;
use Prophet::Collection;
use Prophet::Replica;
use Prophet::CLI::Command;

use List::Util 'first';

has app_class => (
    is      => 'rw',
    isa     => 'ClassName',
    default => 'Prophet::App',
);

has record_class => (
    is      => 'rw',
    isa     => 'ClassName',
    default => 'Prophet::Record',
);

has app_handle => (
    is      => 'rw',
    isa     => 'Prophet::App',
    lazy    => 1,
    handles => [qw/handle resdb_handle config/],
    default => sub {
        $_[0]->app_class->require;
        return $_[0]->app_class->new;
    },
);

has uuid => (
    is            => 'rw',
    isa           => 'Str',
    predicate     => 'has_uuid',
    documentation => "This is the uuid set by the user from the commandline",
);

has type => (
    is  => 'rw',
    isa => 'Str',
    documentation => "This is the type set by the user from the commandline",
);

has primary_commands => (
    is  => 'rw',
    isa => 'ArrayRef',
    documentation => "The commands the user executes from the commandline",
);

has args => (
    metaclass  => 'Collection::Hash',
    is         => 'rw',
    isa        => 'HashRef',
    default    => sub { {} },
    provides   => {
        set    => 'set_arg',
        get    => 'arg',
        exists => 'has_arg',
        delete => 'delete_arg',
        keys   => 'arg_names',
        clear  => 'clear_args',
    },
    documentation => "This is a reference to the key-value pairs passed in on the commandline",
);

has props => (
    metaclass  => 'Collection::Hash',
    is         => 'rw',
    isa        => 'HashRef',
    default    => sub { {} },
    provides   => {
        set    => 'set_prop',
        get    => 'prop',
        exists => 'has_prop',
        delete => 'delete_prop',
        keys   => 'prop_names',
        clear  => 'clear_props',
    },
);

has prop_set => (
    metaclass  => 'Collection::Array',
    is         => 'rw',
    isa        => 'ArrayRef',
    default    => sub { [] },
    auto_deref => 1,
    provides   => {
        push => 'add_to_prop_set',
    },
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
    my $tmp      = $self->primary_commands;
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

    die "I don't know how to parse '" . join( " ", @{ $self->primary_commands } ) . "'. Are you sure that's a valid command?" unless ($class);

    my %constructor_args = (
        cli      => $self,
        commands => $self->primary_commands,
        type     => $self->type,
    );

    # undef causes type constraint violations
    for my $key (keys %constructor_args) {
        delete $constructor_args{$key}
            if !defined($constructor_args{$key});
    }

    $constructor_args{uuid} = $self->uuid
        if $self->has_uuid;

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

=head2 cmp_regex

Returns the regex to use for matching property key/value separators.

=cut

sub cmp_regex { '!=|<>|=~|!~|=|\bne\b' }

=head2 parse_args

This routine pulls arguments (specified by --key=value or --key value) and
properties (specified by --props key=value or -- key=value) passed on the
command line out of ARGV and sticks them in L</args> or L</props> and
L</prop_set> as necessary. Argument keys have leading "--" stripped.

If a key is not given a value on the command line, its value is set to undef.

More complicated separators such as =~ (for regexes) are also handled (see
L</cmp_regex> for details).

=cut

sub parse_args {
    my $self = shift;

    my @primary;
    push @primary, shift @ARGV while ( $ARGV[0] && $ARGV[0] !~ /^--/ );

    # "ticket show 4" should DWIM and "ticket show --id=4"
    $self->set_arg(id => pop @primary)
        if @primary && $primary[-1] =~ /^(?:\d+|[0-9a-f]{8}\-)/i;

    my $collecting_props = 0;

    $self->primary_commands( \@primary );
    my $cmp_re = $self->cmp_regex;

    while (my $name = shift @ARGV) {
        die "$name doesn't look like --argument"
            if !$collecting_props && $name !~ /^--/;

        if ($name eq '--' || $name eq '--props') {
            $collecting_props = 1;
            next;
        }

        my $cmp = '=';
        my $val;

        ($name, $cmp, $val) = ($1, $2, $3)
            if $name =~ /^(.*?)($cmp_re)(.*)$/;
        $name =~ s/^--//;

        # no value specified, pull it from the next argument, unless the next
        # argument is another option
        if (!defined($val)) {
            $val = shift @ARGV
                if @ARGV && $ARGV[0] !~ /^--/;

            no warnings 'uninitialized';

            # but wait! does the value look enough like a comparator? if so,
            # shift off another one (if we can)
            if ($collecting_props) {
                if ($val =~ /^(?:$cmp_re)$/ && @ARGV && $ARGV[0] !~ /^--/) {
                    $cmp = $val;
                    $val = shift @ARGV;
                }
                else {
                    # perhaps they said "foo =~bar"..
                    $cmp = $1 if $val =~ s/^($cmp_re)//;
                }
            }
        }

        if ($collecting_props) {
            $self->add_to_prop_set({
                prop  => $name,
                cmp   => $cmp,
                value => $val,
            });
        }
        else {
            $self->set_arg($name => $val);
        }
    }
}

=head2 set_type_and_uuid

When working with individual records, it is often the case that we'll be
expecting a --type argument and then a mess of other key-value pairs.

This routine figures out and sets C<type> and C<uuid> from the arguments given
on the command-line, if possible. Being unable to figure out a uuid is fatal.

=cut

sub set_type_and_uuid {
    my $self = shift;

    if (my $id = $self->delete_arg('id')) {
        if ($id =~ /^(\d+)$/) {
            $self->set_arg(luid => $id);
        } else {
            $self->set_arg(uuid => $id);
        }
    }

    if ( my $uuid = $self->delete_arg('uuid')) {
        $self->uuid($uuid);
    }
    elsif ( my $luid = $self->delete_arg('luid')) {
        my $uuid = $self->handle->find_uuid_by_luid(luid => $luid);
        die "I have no UUID mapped to the local id '$luid'\n" if !defined($uuid);
        $self->uuid($uuid);
    }
    if ( my $type = $self->delete_arg('type') ) {
        $self->type($type);
    } elsif($self->primary_commands->[-2]) {
        $self->type($self->primary_commands->[-2]);
    }
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
    $self->parse_args();
    $self->set_type_and_uuid();
    if ( my $cmd_obj = $self->_get_cmd_obj() ) {
        $cmd_obj->run();
    }
}

=head2 change_attributes ( args => $hashref, props => $hashref, type => 'str' )

A hook for running a second command from within a command without having       
to use the commandline argument parsing.  

If C<type>, C<uuid>, or C<primary_commands> are not passed in, the values
from the previous command run are used.

=cut

sub change_attributes {
    my $self = shift;
    my %args = @_;

    $self->clear_args();
    $self->clear_props();

    if (my $cmd_args = $args{args}) {
        foreach my $arg (keys %$cmd_args) {
            if ($arg eq 'uuid') {
                $self->uuid($cmd_args->{$arg});
            }
            $self->set_arg($arg => $cmd_args->{$arg});
        }
    }
    if (my $props = $args{props}) {
        foreach my $prop (@$props) {
            my $key = $prop->{prop};
            my $value = $prop->{value};
            $self->set_prop($key => $value);
        }
    }
    if (my $type = $args{type}) {
        $self->type($type);
    }

    if (my $primary_commands = $args{primary_commands}) {
        $self->primary_commands($primary_commands);
    }
}

# clear the prop_set too!
after clear_props => sub {
    my $self = shift;
    $self->prop_set( ( ) );
};

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

after add_to_prop_set => sub {
    my $self = shift;
    my $args = shift;

    $self->set_prop($args->{prop} => $args->{value});
};

__PACKAGE__->meta->make_immutable;
no Moose;

1;

