package Prophet::CLI;
use Moose;
use MooseX::ClassAttribute;

use Prophet;
use Prophet::Record;
use Prophet::Collection;
use Prophet::Replica;
use Prophet::CLI::Command;
use Prophet::CLI::Dispatcher;

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

=head2 dispatcher -> Class

Returns the dispatcher used to dispatch command lines. You'll want to override
this in your subclass.

=cut

sub dispatcher { "Prophet::CLI::Dispatcher" }

=head2 _get_cmd_obj

Attempts to determine a command object based on aliases and the currently
set commands, arguments, and properties. Returns the class on success;
dies on failure.

This routine will use a C<CLI::Command::NotFound> class as a last resort, so
failure should occur rarely if ever.

=cut

sub _get_cmd_obj {
    my $self = shift;

    my $command = join ' ', @{ $self->primary_commands };

    # yeah this kind of sucks but there's no sane way to tell 
    my $class;
    my %dispatcher_args = (
        got_command    => sub { $class = shift },
        dispatching_on => $self->primary_commands,
    );

    $self->dispatcher->run($command, $self, %dispatcher_args);

    die "I don't know how to parse '$command'. Are you sure that's a valid command?" unless $class;

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

Returns the regex to use for matching argument key/value separators.

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

    my $sep = 0;
    my @sep_method = (
        'set_arg',
        'set_prop',
    );

    $self->primary_commands( \@primary );
    my $cmp_re = $self->cmp_regex;

    while (my $name = shift @ARGV) {
        die "$name doesn't look like --argument"
            if $sep == 0 && $name !~ /^--/;

        if ($name eq '--' || $name eq '--props') {
            ++$sep;
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
            if ($val =~ /^(?:$cmp_re)$/ && @ARGV && $ARGV[0] !~ /^--/) {
                $cmp = $val;
                $val = shift @ARGV;
            }
            else {
                # perhaps they said "foo =~bar"..
                $cmp = $1 if $val =~ s/^($cmp_re)//;
            }
        }

        if ($sep == 1) {
            $self->add_to_prop_set({
                prop  => $name,
                cmp   => $cmp,
                value => $val,
            });
        }
        my $setter = $sep_method[$sep] or next;
        $self->$setter($name => $val);
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
        my $uuid = $self->app_handle->handle->find_uuid_by_luid(luid => $luid);
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

=head2 change_attributes ( args => $hashref, props => $arrayref, type => 'str' )

A hook for modifying attributes to prepare for running other commands from
within a command.

C<props> should be an array reference of hashes containing the keys C<prop>,
C<cmp>, and C<value>, such as what is expected by the C<prop_set> attribute
(see L<parse_args>'s use of C<add_to_prop_set>).

C<args> should be a simple array of arg / value pairs.

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
            $self->add_to_prop_set($prop);
        }
    }
    if (my $type = $args{type}) {
        $self->type($type);
    }
    if (my $primary_commands = $args{primary_commands}) {
        $self->primary_commands($primary_commands);
    }
}

=head2 clear_args

Clears all of the current object's set arguments.

=cut

sub clear_args {
    my $self = shift;

    foreach my $arg ($self->arg_names) {
        $self->delete_arg($arg);
    }
}

=head2 clear_props

Clears all of the current object's set properties.

=cut

sub clear_props {
    my $self = shift;

    foreach my $prop ($self->prop_names) {
        $self->delete_prop($prop);
    }
    $self->prop_set( ( ) );
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
    my $ret = eval { $self->run_one_command };
    warn $@ if $@;
    select $ofh if $ofh;
    return $ret;
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;

