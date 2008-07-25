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
    ls   => 'search',
    new  => 'create',
    edit => 'update',
    rm   => 'delete',
    del  => 'delete',
    list => 'search',
);

sub _get_cmd_obj {
    my $self = shift;

    my $aliases  = $self->app_handle->config->aliases;
    my $tmp      = $self->primary_commands;
    if ($aliases->{$tmp->[0]}) {
        @ARGV = split ' ', $aliases->{$tmp->[0]};
        return $self->run_one_command;
    }
    my @commands = map { exists $CMD_MAP{$_} ? $CMD_MAP{$_} : $_ } @{ $tmp };

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

sub _try_to_load_cmd_class {
    my $self = shift;
    my $class = shift;
    Prophet::App->require_module($class);
    return $class if $class->isa('Prophet::CLI::Command');

    warn "Invalid class $class - not a subclass of Prophet::CLI::Command."
        if $class !~ /::$/ # don't warn about "Prophet::CLI::Command::" (which happens on "./bin/sd")
        && Class::MOP::is_class_loaded($class);

    return undef;
}

=head2 parse_args

This routine pulls arguments passed on the command line out of ARGV and sticks them in L</args>. The keys have leading "--" stripped.

=cut

sub parse_args {
    my $self = shift;

    my @primary;
    push @primary, shift @ARGV while ( $ARGV[0] && $ARGV[0] =~ /^\w+$/ && $ARGV[0] !~ /^--/ );

    my $sep = 0;
    my @sep_method = (
        'set_arg',
        'set_prop',
    );

    $self->primary_commands( \@primary );

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
            if $name =~ /^(.*?)(!=|<>|=~|!~|=)(.*)$/;
        $name =~ s/^--//;

        # no value specified, pull it from the next argument, unless the next
        # argument is another option
        $val = shift @ARGV
            if !defined($val) && @ARGV && $ARGV[0] !~ /^--/;

        if ($sep == 1) {
            $self->add_to_prop_set({
                name  => $name,
                cmp   => $cmp,
                value => $val,
            });
        }

        my $setter = $sep_method[$sep] or next;
        $self->$setter($name => $val);
    }
}

=head2 set_type_and_uuid

When working with individual records, it is often the case that we'll be expecting a --type argument and then a mess of other key-value pairs.

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

=head2 args [$ARGS]

Returns a reference to the key-value pairs passed in on the command line

If passed a hashref, sets the args to taht;

=cut

sub run_one_command {
    my $self = shift;
    $self->parse_args();
    $self->set_type_and_uuid();
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
    my $ret = eval { $self->run_one_command };
    warn $@ if $@;
    select $ofh if $ofh;
    return $ret;
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;

