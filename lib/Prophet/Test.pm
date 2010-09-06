package Prophet::Test;
use strict;
use warnings;

use base qw/Test::More Exporter/;
our @EXPORT = qw/as_alice as_bob as_charlie as_david as_user
    repo_uri_for replica_last_rev replica_uuid_for ok_added_revisions replica_uuid
    database_uuid database_uuid_for serialize_conflict serialize_changeset
    in_gladiator diag run_command set_editor set_editor_script load_record
    last_script_stdout last_script_stderr last_script_exit_code
    /;

use Cwd qw/getcwd/;
use File::Path 'rmtree';
use File::Spec;
use File::Temp qw/tempdir tempfile/;
use Params::Validate ':all';
use Prophet::Util;

use Prophet::CLI;

our $REPO_BASE = File::Temp::tempdir();
Test::More->import;
diag( "Replicas can be found in $REPO_BASE" );

# by default, load no configuration file
$ENV{PROPHET_APP_CONFIG} = '';

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

=head2 set_editor_script SCRIPT

Sets the editor that Proc::InvokeEditor uses.

This should be a non-interactive script found in F<t/scripts>.

=cut

sub set_editor_script {
    my ($self, $script) = @_;

    delete $ENV{'VISUAL'};       # Proc::InvokeEditor checks this first
    $ENV{'EDITOR'} = "$^X " . Prophet::Util->catfile(getcwd(), 't', 'scripts', $script);
    Test::More::diag "export EDITOR=" . $ENV{'EDITOR'} . "\n";
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
    $ENV{'PROPHET_EMAIL'} = 'nobody@example.com';
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

}

=head2 repo_path_for($username)

Returns a path on disk for where $username's replica is stored.

=cut

sub repo_path_for {
    my $username = shift;
    return File::Spec->catdir($REPO_BASE => $username);
}

sub config_file_for {
    my $username = shift;

    return File::Spec->catdir($REPO_BASE, $username, 'config');
}

=head2 repo_uri_for($username)

Returns a file:// URI for $USERNAME'S replica (with the correct replica
type prefix).

=cut

sub repo_uri_for {
    my $username = shift;

    my $path = repo_path_for($username);

    return  'file://' . $path;
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
    local $ENV{'PROPHET_REPO'} = repo_path_for($username);
    local $ENV{'PROPHET_EMAIL'}        = $username . '@example.com';
    local $ENV{'PROPHET_APP_CONFIG'} = config_file_for($username);

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
in scalar form or, in array context, the STDOUT in scalar form
*and* the STDERR in scalar form.

Examples:

    run_command('create', '--type=Foo');

=cut

our $CLI_CLASS = 'Prophet::CLI';

sub run_command {
    my $output = '';
    my $error  = '';

    my $original_stdout = *STDOUT;
    my $original_stderr = *STDERR;
    open( my $out_handle, '>', \$output );
    open( my $err_handle, '>', \$error );
    *STDOUT = $out_handle;
    *STDERR = $err_handle;
    $|++; # autoflush

    my $ret = eval {
        local $SIG{__DIE__} = 'DEFAULT';
        $CLI_CLASS->new->run_one_command(@_);
    };
    warn $@ if $@;

    # restore to originals
    *STDOUT = $original_stdout;
    *STDERR = $original_stderr;

    return wantarray ? ($output, $error) : $output;
}

{

=head2 load_record($type, $uuid)

Loads and returns a record object for the record with the given type and uuid.

=cut

    my $connection;
    sub load_record {
        my $type = shift;
        my $uuid = shift;
        require Prophet::Record;
        $connection ||=  Prophet::CLI->new->handle;
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
