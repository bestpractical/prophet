use strict;
use warnings;

package Prophet::Test;
use base qw/Test::More Exporter/;
our @EXPORT = qw/as_alice as_bob as_charlie as_david as_user run_ok repo_uri_for run_script run_output_matches run_output_matches_unordered replica_last_rev replica_uuid_for ok_added_revisions replica_uuid database_uuid database_uuid_for
    serialize_conflict serialize_changeset in_gladiator diag is_script_output run_command set_editor load_record
    /;

use File::Path 'rmtree';
use File::Spec;
use File::Temp qw/tempdir tempfile/;
use Test::Exception;
use IPC::Run3 'run3';
use Params::Validate ':all';
use Scalar::Defer qw/lazy defer force/;
use Prophet::Util;

use Prophet::CLI;

our $REPO_BASE = File::Temp::tempdir();
Test::More->import;
diag( "Replicas can be found in $REPO_BASE" );

{
    no warnings 'redefine';
    require Test::More;
    sub Test::More::diag {    # bad bad bad # convenient convenient convenient
        Test::More->builder->diag(@_) if ( $Test::Harness::Verbose || $ENV{'TEST_VERBOSE'} );
    }
}

our $EDIT_TEXT = sub { shift };
do {
    no warnings 'redefine';
    *Prophet::CLI::Command::edit_text = sub {
        my $self = shift;
        $EDIT_TEXT->(@_);
    };
};

=head2 set_editor($code)

Sets the subroutine that Prophet should use instead of
C<Prophet::CLI::Command::edit_text> (as this routine invokes an interactive
editor) to $code.

=cut

sub set_editor {
    $EDIT_TEXT = shift;
}

=head2 import_extra($class, $args)

=cut

sub import_extra {
    my $class = shift;
    my $args  = shift;

    Test::More->export_to_level(2);

    # Now, clobber Test::Builder::plan (if we got given a plan) so we
    # don't try to spit one out *again* later
    if ( $class->builder->has_plan ) {
        no warnings 'redefine';
        *Test::Builder::plan = sub { };
    }

    delete $ENV{'PROPHET_APP_CONFIG'};
    $ENV{'EMAIL'} = 'nobody@example.com';
}

=head2 in_gladiator($code)

Run the given code using L<Devel::Gladiator>.

=cut

sub in_gladiator (&) {
    my $code = shift;
    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my $types;
    eval { require Devel::Gladiator; };
    if ($@) {
        warn 'Devel::Gladiator not found';
        return $code->();
    }
    for ( @{ Devel::Gladiator::walk_arena() } ) {
        $types->{ ref($_) }--;
    }

    $code->();
    for ( @{ Devel::Gladiator::walk_arena() } ) {
        $types->{ ref($_) }++;
    }
    map { $types->{$_} || delete $types->{$_} } keys %$types;
    warn YAML::Syck::Dump($types);

}

=head2 run_script($script, $args, $stdout, $stderr)

Runs the script $script as a perl script, setting the @INC to the same as
our caller.

$script is the name of the script to be run (such as 'prophet'). $args is a
reference to an array of arguments to pass to the script. $stdout and $stderr
are both optional; if passed in, they will be passed to L<IPC::Run3>'s run3
subroutine as its $stdout and $stderr args.  Otherwise, this subroutine will
create scalar references to pass to run3 instead (which are treated as strings
for STDOUT/STDERR to be written to).

Returns run3's return value and, if no $stdout and $stderr were passed in, the
STDOUT and STDERR of the script that was run.

=cut

sub run_script {
    my $script = shift;
    my $args = shift || [];
    my ( $stdout, $stderr ) = @_;
    my ( $new_stdout, $new_stderr, $return_stdouterr );
    if (!ref($stdout) && !ref($stderr)) {
        ($stdout, $stderr, $return_stdouterr) = (\$new_stdout, \$new_stderr, 1);
    }
    my @cmd = _get_perl_cmd($script);

    local $ENV{IN_PROPHET_TEST_COMMAND} = 1;

    #    diag(join(' ', @cmd, @$args));
    my $ret = run3 [ @cmd, @$args ], undef, $stdout, $stderr;
    # we don't actually want to die if the run command returned an error code
    # Carp::croak $stderr          if $?;
    #diag( "STDOUT: " . $stdout ) if ($stdout);
    #diag( "STDERR: " . $stderr ) if ($stderr);

    #Test::More::diag $stderr;
    return $return_stdouterr ? ( $ret, $$stdout, $$stderr ) : $ret;
}

our $RUNCNT;

sub _get_perl_cmd {
    my ($tmp, $i) = (Prophet::Util->updir($0), 0);
    while ( ! -d File::Spec->catdir($tmp, 'bin') && $i++ < 10 ) {
        $tmp = Prophet::Util->updir($tmp);
    }
    
    my $base_dir = File::Spec->catdir($tmp, 'bin');
    die "couldn't find bin dir" unless -d $base_dir;

    my $script = shift;
    my @cmd = ( $^X, ( map {"-I$_"} @INC ) );
    push @cmd, '-MDevel::Cover' if $INC{'Devel/Cover.pm'};
    if ( $INC{'Devel/DProf.pm'} ) {
        push @cmd, '-d:DProf';
        $ENV{'PERL_DPROF_OUT_FILE_NAME'} = 'tmon.out.' . $$ . '.' . $RUNCNT++;
    }
    push @cmd, File::Spec->catdir($base_dir => $script);
    return @cmd;
}

=head2 run_ok($script, $args, $msg)

Runs the script, checking that it didn't error out.

$script is the name of the script to be run (e.g. 'prophet'). $args
is an optional reference to an array of arguments to pass to the
script when it is run. $msg is an optional message to print with
the test. If $args is not specified, you can still pass in
a $msg.

Returns nothing of interest.

=cut

sub run_ok {
    my $script = shift;
    my $args   = shift if ( ref $_[0] eq 'ARRAY' );
    my $msg    = (@_) ? shift : '';

    local $Test::Builder::Level = $Test::Builder::Level + 1;

    lives_and {
        local $Test::Builder::Level = $Test::Builder::Level + 1;
        my ( $ret, $stdout, $stderr ) = run_script( $script, $args );
        # diag("STDOUT: " . $stdout) if ($stdout);
        # diag("STDERR: " . $stderr) if ($stderr);
        ok($ret, $msg);
    };
}

=head2 is_script_output($scriptname \@args, \@stdout_match, \@stderr_match, $msg)

Runs $scriptname, checking to see that its output matches.

$args is an array reference of args to pass to the script. $stdout_match and
$stderr_match are references to arrays of expected lines. $msg is a string
message to display with the test. $stderr_match and $msg are optional. (As is
$stdout_match if for some reason you expect your script to have no output at
all. But that would be silly, wouldn't it?)

Allows regex matches as well as string equality (lines in $stdout_match and
$stderr_match may be Regexp objects).

=cut

sub is_script_output {
    my ( $script, $args, $exp_stdout, $exp_stderr, $msg ) = @_;
    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my $stdout_err = [];
    $exp_stderr ||= [];

    my $ret = run_script($script, $args,
        _mk_cmp_closure( $exp_stdout, $stdout_err ),    # stdout
        _mk_cmp_closure( $exp_stderr, $stdout_err ),    # stderr
    );

    _check_cmp_closure_output($script, $msg, $args, $exp_stdout, $stdout_err);
}

=head2 _mk_cmp_closure($expected, $error)

$expected is a reference to an array of expected output lines, and
$error is an array reference for storing error messages.

Returns a subroutine that takes a line of output and compares it
to the next line in $expected. You can, for example, pass this
subroutine to L<IPC::Run3>::run3 and it will compare the output
of the script being run to the expected output. After the script
is done running, errors will be in $error.

If a line in $expected is a Regexp reference (made with e.g.
qr/foo/), the subroutine will check for a regexp match rather
than string equality.

=cut

sub _mk_cmp_closure {
    my ( $exp, $err ) = @_;
    my $line = 0;

    $exp = [$exp] if ref($exp) ne 'ARRAY';

    sub {
        my $output = shift;
        chomp $output;
        ++$line;
        unless (@$exp) {
            push @$err, "$line: got $output";
            return;
        }
        my $item = shift @$exp;
        push @$err, "$line: got ($output), expect ($item)\n"
            unless ref($item) eq 'Regexp'
            ? ( $output =~ m/$item/ )
            : ( $output eq $item );
    }
}

# XXX note that this sub doesn't check to make sure we got
# all the errors we were expecting (there can be more lines
# in the expected stderr than the received stderr as long
# as they match up until the end of the received stderr --
# the same isn't true of stdout)
sub _check_cmp_closure_output {
    my ($script, $msg, $args, $exp_stdout, $stdout_err) = @_;

    for my $line (@$exp_stdout) {
        next if !defined $line;
        push @$stdout_err, "got nothing, expected: $line";
    }

    my $test_name = join( ' ', $msg ? "$msg:" : '', $script, @$args );
    is(scalar(@$stdout_err), 0, $test_name);

    if (@$stdout_err) {
        diag( "Different in line: " . join( "\n", @$stdout_err ) );
    }
}

=head2 run_output_matches($script, $args, $exp_stdout, $exp_stderr, $msg)

A wrapper around L<is_script_output> that also checks to make sure
the test runs without throwing an exception.

=cut

sub run_output_matches {
    my ( $script, $args, $expected, $stderr, $msg ) = @_;
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    lives_and {
        local $Test::Builder::Level = $Test::Builder::Level + 3;
        is_script_output($script, $args, $expected, $stderr, $msg);
    };
}

=head2 run_output_matches_unordered($script, $args, $exp_stdout, $exp_stderr, $msg)

This subroutine has exactly the same functionality as run_output_matches, but
doesn't impose a line ordering when comparing the expected and received
outputs.

=cut

sub run_output_matches_unordered {
    my ($cmd, $args, $stdout, $stderr, $msg) = @_;
    $stderr ||= [];

    my ($val, $out, $err)  = run_script( $cmd, $args );

    local $Test::Builder::Level = $Test::Builder::Level + 1;

    # Check if each line matches a line in the expected output and
    # delete that line if we have a match. If no match is found,
    # add an error.
    my $errors = [];
    my @lines = split /\n/, $out;
    OUTPUT: while (my $line = shift @lines) {
        for my $exp_line (@$stdout) {
            if ((ref($exp_line) eq 'Regexp' ? ( $line =~ m/$exp_line/ ) :
                                            ( $line eq $exp_line ))) {
                # remove the found element from the array of expected output
                $stdout = [grep { $_ ne $exp_line } @$stdout];
                next OUTPUT;
            }
        }
        # we didn't find a match
        push @$errors, "couldn't find match for ($line)\n";
    }

    # do the same for STDERR
    @lines = split /\n/, $err;
    ERROR: while (my $line = shift @lines) {
        for my $exp_line (@$stderr) {
            if ((ref($exp_line) eq 'Regexp' ? ( $line =~ m/$exp_line/ ) :
                                            ( $line eq $exp_line ))) {
                # remove the found element from the array of expected output
                $stderr = [grep { $_ ne $exp_line } @$stderr];
                next ERROR;
            }
        }
        # we didn't find a match
        push @$errors, "couldn't find match for ($line)\n";
    }

    # add any expected lines that we didn't find to the errors
    for my $exp_line (@$stdout, @$stderr) {
        push @$errors, "got nothing, expected: $exp_line";
    }

    my $test_name = join( ' ', $msg ? "$msg:" : '', $cmd, @$args );
    is(scalar(@$errors), 0, $test_name);

    if (@$errors) {
        diag( "Errors: " . join( "\n", @$errors ) );
    }
}

=head2 repo_path_for($username)

Returns a path on disk for where $username's replica is stored.

=cut

sub repo_path_for {
    my $username = shift;
    return File::Spec->catdir($REPO_BASE => $username);
}

=head2 repo_uri_for($username)

Returns a file:// URI for $USERNAME'S replica (with the correct replica
type prefix).

=cut

use constant IS_WIN32 => ( $^O eq 'MSWin32' );

sub repo_uri_for {
    my $username = shift;

    my $path = repo_path_for($username);
    $path =~ s{^|\\}{/}g if IS_WIN32;

    return Prophet::App->default_replica_type . ':file://' . $path;
}

=head2 replica_uuid

Returns the UUID of the test replica.

=cut

sub replica_uuid {
    my $self = shift;
    my $cli  = Prophet::CLI->new();
    return $cli->handle->uuid;
}

=head2 database_uuid

Returns the UUID of the test database.

=cut

sub database_uuid {
    my $self = shift;
    my $cli  = Prophet::CLI->new();
    return eval { $cli->handle->db_uuid};
}

=head2 replica_last_rev

Returns the sequence number of the last change in the test replica.

=cut

sub replica_last_rev {
    my $cli = Prophet::CLI->new();
    return $cli->handle->latest_sequence_no;
}

=head2 as_user($username, $coderef)

Run this code block as $username.  This routine sets up the %ENV hash so that
when we go looking for a repository, we get the user's repo.

=cut

our %REPLICA_UUIDS;
our %DATABASE_UUIDS;

sub as_user {
    my $username = shift;
    my $coderef  = shift;
    local $ENV{'PROPHET_USER'} = $username;
    local $ENV{'PROPHET_REPO'} = repo_path_for($username);
    local $ENV{'EMAIL'}        = $username . '@example.com';

    my $ret = $coderef->();

    $REPLICA_UUIDS{$username} = replica_uuid();
    $DATABASE_UUIDS{$username} = database_uuid();

    return $ret;
}

=head2 replica_uuid_for($username)

Returns the UUID of the given user's test replica.

=cut

sub replica_uuid_for {
    my $user = shift;
    return $REPLICA_UUIDS{$user};
}

=head2 database_uuid_for($username)

Returns the UUID of the given user's test database.

=cut

sub database_uuid_for {
    my $user = shift;
    return $DATABASE_UUIDS{$user};
}

=head2 ok_added_revisions( { CODE }, $numbers_of_new_revisions, $msg)

Checks that the given code block adds the given number of changes to the test
replica. $msg is optional and will be printed with the test if given.

=cut

sub ok_added_revisions (&$$) {
    my ( $code, $num, $msg ) = @_;
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    my $last_rev = replica_last_rev();
    $code->();
    is( replica_last_rev(), $last_rev + $num, $msg );
}

=head2 serialize_conflict($conflict_obj)

Returns a simple, serialized version of a L<Prophet::Conflict> object suitable
for comparison in tests.

The serialized version is a hash reference containing the following keys:
    meta => { original_source_uuid => 'source_replica_uuid' }
    records => { 'record_uuid' =>
                   { change_type => 'type',
                     props => { propchange_name => { source_old => 'old_val',
                                                     source_new => 'new_val',
                                                     target_old => 'target_val',
                                                   }
                              }
                   },
                 'another_record_uuid' =>
                   { change_type => 'type',
                     props => { propchange_name => { source_old => 'old_val',
                                                     source_new => 'new_val',
                                                     target_old => 'target_val',
                                                   }
                              }
                   },
               }

=cut

sub serialize_conflict {
    my ($conflict_obj) = validate_pos( @_, { isa => 'Prophet::Conflict' } );
    my $conflicts;
    for my $change ( @{ $conflict_obj->conflicting_changes } ) {
        $conflicts->{meta} = { original_source_uuid => $conflict_obj->changeset->original_source_uuid };
        $conflicts->{records}->{ $change->record_uuid } = { change_type => $change->change_type, };

        for my $propchange ( @{ $change->prop_conflicts } ) {
            $conflicts->{records}->{ $change->record_uuid }->{props}->{ $propchange->name } = {
                source_old => $propchange->source_old_value,
                source_new => $propchange->source_new_value,
                target_old => $propchange->target_value
                }

        }
    }
    return $conflicts;
}

=head2 serialize_changeset($changeset_obj)

Returns a simple, serialized version of a L<Prophet::ChangeSet> object
suitable for comparison in tests (a hash).

=cut

sub serialize_changeset {
    my ($cs) = validate_pos( @_, { isa => 'Prophet::ChangeSet' } );

    return $cs->as_hash;
}

=head2 run_command($command, @args)

Run the given command with (optionally) the given args using a new
L<Prophet::CLI> object. Returns the standard output of that command
in scalar form.

Examples:

    run_command('create', '--type=Foo');

=cut

sub run_command {
    my $output = '';
    open my $handle, '>', \$output;
    Prophet::CLI->new->invoke($handle, @_);
    return $output;
}

{
    my $connection = lazy { Prophet::CLI->new->handle };

=head2 load_record($type, $uuid)

Loads and returns a record object for the record with the given type and uuid.

=cut

    sub load_record {
        my $type = shift;
        my $uuid = shift;
        require Prophet::Record;
        my $record = Prophet::Record->new(handle => $connection, type => $type);
        $record->load(uuid => $uuid);
        return $record;
    }
}

=head2 as_alice CODE, as_bob CODE, as_charlie CODE, as_david CODE

Runs CODE as alice, bob, charlie or david.

=cut

sub as_alice (&)  { as_user( alice   => shift ) }
sub as_bob (&)    { as_user( bob     => shift ) }
sub as_charlie(&) { as_user( charlie => shift ) }
sub as_david(&)   { as_user( david   => shift ) }

# END {
#     for (qw(alice bob charlie david)) {

#         #     as_user( $_, sub { rmtree [ $ENV{'PROPHET_REPO'} ] } );
#     }
# }

1;
