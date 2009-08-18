package Prophet::CLI::Command;
use Any::Moose;

use Prophet::CLI;
use Params::Validate qw(validate);

has cli => (
    is => 'rw',
    isa => 'Prophet::CLI',
    weak_ref => 1,
    handles => [
        qw/app_handle handle config/,
    ],
);

has context => (
    is => 'rw',
    isa => 'Prophet::CLIContext',
    handles => [
        qw/args  set_arg  arg  has_arg  delete_arg  arg_names/,
        qw/props set_prop prop has_prop delete_prop prop_names/,
        'add_to_prop_set', 'prop_set',
    ],

);

sub ARG_TRANSLATIONS {
    my $self = shift;
    return (    'v' => 'verbose',
                'a' => 'all' );
}

=head2 Registering argument translations

This is the Prophet CLI's way of supporting short forms for arguments,
e.g. you want to let '-v' be able to used for the same purpose as
'--verbose' without dirtying your code checking both or manually
setting them if they exist. We want it to be as easy as possible
to have short commands.

To use, have your command subclass do:

    sub ARG_TRANSLATIONS { shift->SUPER::ARG_TRANSLATIONS(),  f => 'file' };

You can register as many translations at a time as you want.
The arguments will be translated when the command object is
instantiated. If an arg already exists in the arg translation
table, it is overwritten with the new value.

=cut

sub _translate_args {
    my $self = shift;
    my %translations = $self->ARG_TRANSLATIONS;

    for my $arg (keys %translations) {
        $self->set_arg($translations{$arg}, $self->arg($arg))
            if $self->has_arg($arg);
    }
}

# run arg translations on object instantiation
sub BUILD {
    my $self = shift;

    $self->_translate_args();

    return $self;
}

sub fatal_error {
    my $self   = shift;
    my $reason = shift;

    # always skip this fatal_error function when generating a stack trace
    local $Carp::CarpLevel = $Carp::CarpLevel + 1;

    die $reason . "\n";
}

=head2 require_uuid

Checks to make sure the uuid attribute is set. Prints an error and dies
with the command's usage string if it is not set.

=cut

sub require_uuid {
    my $self    = shift;

    if (!$self->has_uuid) {
        my $type = $self->type;
        my $name = (split /::/, $self->meta->name)[-1];
        warn "No UUID or LUID given!\n";
        $self->print_usage;
    }
}

=head2 edit_text [text] -> text

Filters the given text through the user's C<$EDITOR> using
L<Proc::InvokeEditor>.

=cut

sub edit_text {
    my $self = shift;
    my $text = shift;

    # don't invoke the editor in a script, the test will appear to hang
    #die "Tried to invoke an editor in a test script!" if $ENV{IN_PROPHET_TEST_COMMAND};

    require Proc::InvokeEditor;
    return scalar Proc::InvokeEditor->edit($text);
}




=head2 edit_hash hash => hashref, ordering => arrayref

Filters the hash through the user's C<$EDITOR> using L<Proc::InvokeEditor>.

No validation is done on the input or output.

If the optional ordering argument is specified, hash keys will be presented
in that order (with unspecified elements following) for edit.

If the record class for the current type defines a C<immutable_props>
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
    my @do_not_edit = $record->can('immutable_props') ? $record->immutable_props : ();

    if (@ordering) {
        # add any keys not in @ordering to the end of it
        my %keys_in_ordering;
        map { $keys_in_ordering{$_} = 1 if exists($hash->{$_}) } @ordering;
        map { push @ordering, $_ if !exists($keys_in_ordering{$_}) } keys %$hash;
    } else {
        @ordering = sort keys %$hash;
    }

    # filter out props we don't want to present for editing
    my %do_not_edit = map { $_ => 1 } @do_not_edit;
    @ordering = grep { !$do_not_edit{$_}  } @ordering;

    my $input = join "\n", map { "$_: $hash->{$_}" } @ordering;

    my $output = $self->edit_text($input);

    die "Aborted.\n" if $input eq $output;

    # parse the output
    my $filtered = {};
    for my $line (split "\n", $output) {
        if ($line =~ m/^([^:]+):\s*(.*)$/) {
            my $prop = $1;
            my $val = $2;
            # don't return empty values
            $filtered->{$prop} = $val unless !($val);
        }
    }
    no warnings 'uninitialized';

    # if a key is deleted intentionally, set its value to ''
    for my $prop (keys %$hash) {
        if (!exists $filtered->{$prop} and ! exists $do_not_edit{$prop}) {
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
        %props = (%{ $defaults }, %{ $self->props });
    } else {
        %props = %{$self->props};
    }

    if ($self->has_arg($arg)) {
        return $self->edit_hash(hash => \%props, ordering => $args{'ordering'});
    }

    return \%props;
}

=head2 prompt_choices question

Asks user the question and returns 0 if answer was the second choice,
1 otherwise. (First choice is the default.)

=cut

sub prompt_choices {
    my $self = shift;
    my ($choice1, $choice2, $question) = @_;

    $choice1 = uc $choice1;     # default is capsed
    $choice2 = lc $choice2;     # non-default is lowercased

    Prophet::CLI->end_pager();
    print "$question [$choice1/$choice2]: ";

    chomp( my $answer = <STDIN> );

    Prophet::CLI->start_pager();

    return $answer !~ /^$choice2$/i;
}

=head2 prompt_Yn question

Asks user the question and returns true if answer was positive or false
otherwise. Default answer is 'Yes' (returns true).

=cut

sub prompt_Yn {
    my $self = shift;
    my $msg = shift;

    return $self->prompt_choices( 'y', 'n', $msg );
}

# Create a new [replica] config file section for the given replica if
# it hasn't been seen before (config section doesn't already exist)
sub record_replica_in_config {
    my $self = shift;
    my $replica_url = shift;
    my $replica_uuid = shift;
    my $url_variable = shift || 'url';

    my %previous_sources_by_uuid
        = $self->app_handle->config->sources(
            by_variable => 1,
            variable => 'uuid',
        );

    my $found_prev_replica = $previous_sources_by_uuid{$replica_uuid};

    if ( !$found_prev_replica ) {
        # replica section doesn't exist at all; create a new one
	    my $url = $replica_url;
        $self->app_handle->config->group_set(
            $self->app_handle->config->replica_config_file,
            [
            {
                key => "replica.$url.$url_variable",
                value => $replica_url,
            },
            {
                key => "replica.$url.uuid",
                value => $replica_uuid,
            },
            ],
        );
    }
    elsif ( $found_prev_replica ne $replica_url ) {
        # We're publishing to a different place than where it was published
        # to previously--we don't want to end up with a multivalue in the
        # config file, so just replace the old value.
        my $name = $self->app_handle->display_name_for_replica($replica_uuid);
        $self->app_handle->config->set(
            filename => $self->app_handle->config->replica_config_file,
            key => "replica.$name.$url_variable",
            value => $replica_url,
        );
    }
}

=head2 print_usage

Print the command's usage message to STDERR and die. Commands should
implement C<usage_msg>, which returns the usage message.

If the usage message method needs arguments passed in, use a closure.

=cut

sub print_usage {
    my $self = shift;
    my %args = (
        usage_method      => sub { $self->usage_msg },
        @_,
    );

    die $args{usage_method}();
}

=head2 get_cmd_and_subcmd_names [no_type => 1]

Gets the name of the script that was run and the primary commands that were
specified on the command-line. If a true boolean is passed in as C<no_type>,
won't add '<record-type>' to the subcmd if no type was passed in via the
primary commands.

=cut

sub get_cmd_and_subcmd_names {
    my $self = shift;
    my %args = @_;

    my $cmd = $self->cli->get_script_name;
    my @primary_commands = @{ $self->context->primary_commands };

    # if primary commands was only length 1, the type was not specified
    # and we should indicate that a type is expected
    push @primary_commands, '<record-type>'
        if @primary_commands <= 1 && !$args{no_type};

    my $type_and_subcmd = join( q{ }, @primary_commands );

    return ($cmd, $type_and_subcmd);
}

__PACKAGE__->meta->make_immutable;
no Any::Moose;

1;

