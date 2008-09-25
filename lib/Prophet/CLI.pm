package Prophet::CLI;
use Moose;
use MooseX::ClassAttribute;

use Prophet;
use Prophet::Replica;
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


=head2 dispatcher_class -> Class

Returns the dispatcher class used to dispatch command lines. You'll want to
override this in your subclass.

=cut

sub dispatcher_class { "Prophet::CLI::Dispatcher" }

=head2 run_one_command

Runs a command specified by commandline arguments given in an
ARGV-like array of argumnents and key value pairs . To use in a
commandline front-end, create a L<Prophet::CLI> object and pass in
your main app class as app_class, then run this routine.

Example:

 my $cli = Prophet::CLI->new({ app_class => 'App::SD' });
 $cli->run_one_command(@ARGV);

=cut

sub run_one_command {
    my $self = shift;
    my @args = (@_);

    # really, we shouldn't be doing this stuff from the command dispatcher

    $self->context(Prophet::CLIContext->new( app_handle => $self->app_handle));
    $self->context->setup_from_args(@args);

    my $args = $self->context->primary_commands;
    my $command = join ' ', @$args;

    my $dispatcher = $self->dispatcher_class->new(
        cli            => $self,
        dispatching_on => $args,
    );

    $dispatcher->run($command, $dispatcher);
}

=head2 invoke outhandle, ARGV_COMPATIBLE_ARRAY

Run the given command. If outhandle is true, select that as the file handle
for the duration of the command.

=cut

sub invoke {
    my ($self, $output, @args) = @_;
    my $ofh;

    $ofh = select $output if $output;
    my $ret = eval {
        local $SIG{__DIE__} = 'DEFAULT';
        $self->run_one_command(@args);
    };
    warn $@ if $@;
    select $ofh if $ofh;
    return $ret;
}

=head2 edit_text [text] -> text

Filters the given text through the user's C<$EDITOR> using
L<Proc::InvokeEditor>.

=cut

sub edit_text {
    my $self = shift;
    my $text = shift;

    # don't invoke the editor in a script, the test will appear to hang
    die "Tried to invoke an editor in a test script!"
        if $ENV{IN_PROPHET_TEST_COMMAND};

    require Proc::InvokeEditor;
    return scalar Proc::InvokeEditor->edit($text);
}

=head2 edit_hash hash => hashref, ordering => arrayref

Filters the hash through the user's C<$EDITOR> using L<Proc::InvokeEditor>.

No validation is done on the input or output.

If the optional ordering argument is specified, hash keys will be presented
in that order (with unspecified elements following) for edit.

If the record class for the current type defines a C<props_not_to_edit>
routine, those props will not be presented for editing.

False values are not returned unless a prop is removed from the output.

=cut

sub edit_hash {
    my $self = shift;
    validate( @_, { hash => 1, ordering => 0 } );
    my %args = @_;
    my $hash = $args{'hash'};
    my @ordering = @{ $args{'ordering'} || [] };
    my $record = $self->_get_record_object;
    my $do_not_edit = $record->can('props_not_to_edit') ? $record->props_not_to_edit : '';

    if (@ordering) {
        # add any keys not in @ordering to the end of it
        my %keys_in_ordering;
        map { $keys_in_ordering{$_} = 1 if exists($hash->{$_}) } @ordering;
        map { push @ordering, $_ if !exists($keys_in_ordering{$_}) } keys %$hash;
    } else {
        @ordering = sort keys %$hash;
    }

    # filter out props we don't want to present for editing
    @ordering = grep { !/$do_not_edit/ } @ordering;

    my $input = join "\n", map { "$_: $hash->{$_}" } @ordering;

    my $output = $self->edit_text($input);

    die "Aborted.\n" if $input eq $output;

    # parse the output
    my $filtered = {};
    foreach my $line (split "\n", $output) {
        if ($line =~ m/^([^:]+):\s*(.*)$/) {
            my $prop = $1;
            my $val = $2;
            # don't return empty values
            $filtered->{$prop} = $val unless !($val);
        }
    }
    no warnings 'uninitialized';

    # if a key is deleted intentionally, set its value to ''
    foreach my $prop (keys %$hash) {
        if (!exists $filtered->{$prop} and $prop =~ !/$do_not_edit/) {
            $filtered->{$prop} = '';
        }
    }

    # filter out unchanged keys as they clutter changesets if they're set again
    map { delete $filtered->{$_} if $hash->{$_} eq $filtered->{$_} } keys %$filtered;

    return $filtered;
}

=head2 edit_props arg => str, defaults => hashref, ordering => arrayref

Returns a hashref of the command's props mixed in with any default props.
If the "arg" argument is specified, (default "edit", use C<undef> if you only
want default arguments), then L</edit_hash> is invoked on the property list.

If the C<ordering> argument is specified, properties will be presented in that
order (with unspecified props following) if filtered through L</edit_hash>.

=cut

sub edit_props {
    my $self = shift;
    my %args = @_;
    my $arg  = $args{'arg'} || 'edit';
    my $defaults = $args{'defaults'};

    my %props;
    if ($defaults) {
        %props = (%{ $defaults }, %{ $self->context->props });
    } else {
        %props = %{$self->context->props};
    }

    if ($self->context->has_arg($arg)) {
        return $self->edit_hash(hash => \%props, ordering => $args{'ordering'});
    }

    return \%props;
}


__PACKAGE__->meta->make_immutable;
no Moose;

1;

