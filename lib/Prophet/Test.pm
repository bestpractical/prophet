use strict;
use warnings;

package Prophet::Test;
use base qw/Test::More Exporter/;
our @EXPORT = qw/as_alice as_bob as_charlie as_david as_user run_ok repo_uri_for run_script run_output_matches run_output_matches_unordered replica_last_rev replica_merge_tickets replica_uuid_for fetch_newest_changesets ok_added_revisions replica_uuid database_uuid database_uuid_for
    serialize_conflict serialize_changeset in_gladiator diag is_script_output run_command set_editor load_record
    /;

use File::Path 'rmtree';
use File::Temp qw/tempdir/;
use Path::Class 'dir';
use Test::Exception;
use IPC::Run3 'run3';
use Params::Validate ':all';
use Scalar::Defer qw/lazy defer force/;

use Prophet::CLI;

our $REPO_BASE = File::Temp::tempdir();
Test::More->import;
diag( "Replicas can be found in" . $REPO_BASE );

our $EDIT_TEXT = sub { shift };
do {
    no warnings 'redefine';
    *Prophet::CLI::Command::edit_text = sub {
        my $self = shift;
        $EDIT_TEXT->(@_);
    };
};

sub set_editor {
    $EDIT_TEXT = shift;
}

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
$ENV{'PROPHET_APP_CONFIG'} = 't/testing.conf';
}

{
    no warnings 'redefine';
    require Test::More;
    sub Test::More::diag {    # bad bad bad # convenient convenient convenient
        Test::More->builder->diag(@_) if ( $Test::Harness::Verbose || $ENV{'TEST_VERBOSE'} );
    }
}

sub in_gladiator (&) {
    my $code = shift;
    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my $types;
    eval { require Devel::Gladiator; };
    if ($@) {
        warn 'Get Devel::Gladiator from http://code.sixapart.com/svn/Devel-Gladiator/trunk/ and harass sky@crucially.net to CPAN it';
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

=head2 run_script SCRIPT_NAME [@ARGS]

Runs the script SCRIPT_NAME as a perl script, setting the @INC to the same as our caller

=cut

sub run_script {
    my $script = shift;
    my $args = shift || [];
    my ( $stdout, $stderr );
    my @cmd = _get_perl_cmd($script);

    #    diag(join(' ', @cmd, @$args));
    my $ret = run3 [ @cmd, @$args ], undef, \$stdout, \$stderr;
    Carp::croak $stderr          if $?;
    diag( "STDOUT: " . $stdout ) if ($stdout);
    diag( "STDERR: " . $stderr ) if ($stderr);

    #Test::More::diag $stderr;
    return ( $ret, $stdout, $stderr );
}

=head2 run_ok SCRIPT_NAME [@ARGS] (<- optional hashref), optional message

Runs the script, checking that it didn't error out.

=cut

sub run_ok {
    my $script = shift;
    my $args   = shift if ( ref $_[0] eq 'ARRAY' );
    my $msg    = shift if (@_);

    local $Test::Builder::Level = $Test::Builder::Level + 1;

    lives_and {
        local $Test::Builder::Level = $Test::Builder::Level + 1;
        my ( $ret, $stdout, $stderr ) = ( run_script( $script, $args ), $msg );

        #diag("STDOUT: " . $stdout) if ($stdout);
        #diag("STDERR: " . $stderr) if ($stderr);
        ok($ret, $msg);
    };
}

sub _mk_cmp_closure {
    my ( $exp, $err ) = @_;
    my $line = 0;

    $exp = ref($exp) eq 'ARRAY' ? $exp : [$exp];

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
            unless ref($item)
            ? ( $output =~ m/$item/ )
            : ( $output eq $item );
        }
}

=head2 is_script_output SCRIPTNAME \@ARGS, \@STDOUT_MATCH, \@STDERR_MATCH, $MSG

Runs the script, checking to see that its output matches



=cut

our $RUNCNT;

sub _get_perl_cmd {
    my $base_dir = Path::Class::File->new($0)->dir->parent->subdir('bin');

    my $script = shift;
    my @cmd = ( $^X, ( map {"-I$_"} @INC ) );
    push @cmd, '-MDevel::Cover' if $INC{'Devel/Cover.pm'};
    if ( $INC{'Devel/DProf.pm'} ) {
        push @cmd, '-d:DProf';
        $ENV{'PERL_DPROF_OUT_FILE_NAME'} = 'tmon.out.' . $$ . '.' . $RUNCNT++;
    }
    push @cmd, $base_dir->file($script);
    return @cmd;
}

sub is_script_output {
    my ( $script, $arg, $exp_stdout, $exp_stderr, $msg ) = @_;

    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my $stdout_err = [];
    $exp_stderr ||= [];
    my @cmd = _get_perl_cmd($script);

    my $ret = run3 [ @cmd, @$arg ], undef, _mk_cmp_closure( $exp_stdout, $stdout_err ),    # stdout
        _mk_cmp_closure( $exp_stderr, $stdout_err );                                       # stderr

    for my $line(@$exp_stdout) {
        next if !defined $line;
        push @$stdout_err, "got nothing, expected: $line";
    }

    my $test_name = join( ' ', $msg ? "$msg:" : '', $script, @$arg );
    is(scalar(@$stdout_err), 0, $test_name);
    if (@$stdout_err) {
        diag( "Different in line: " . join( ',', @$stdout_err ) );
    }
}

sub run_output_matches {
    my ( $script, $args, $expected, $stderr, $msg ) = @_;
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    lives_and {
        local $Test::Builder::Level = $Test::Builder::Level + 3;
        is_script_output($script, $args, $expected, $stderr, $msg);
    };
}

sub run_output_matches_unordered {
    my $cmd = shift;
    my $args = shift;
    my $output = shift;
    my ($val, $out, $err)  = run_script( $cmd, $args);

    local $Test::Builder::Level = $Test::Builder::Level + 1;
    is_deeply([sort split(/\n/,$out)], [sort @$output]);
}

=head2 repo_path_for $USERNAME

Returns a path on disk for where $USERNAME's replica is stored

=cut

sub repo_path_for {
    my $username = shift;
    return dir($REPO_BASE)->subdir($username);
}

=head2 repo_uri_for $USERNAME

Returns a subversion file:// URI for $USERNAME'S replica

=cut

use constant IS_WIN32 => ( $^O eq 'MSWin32' );

sub repo_uri_for {
    my $username = shift;

    my $path = repo_path_for($username);
    $path =~ s{^|\\}{/}g if IS_WIN32;

    return Prophet::App->default_replica_type . ':file://' . $path;
}

sub replica_uuid {
    my $self = shift;
    my $cli  = Prophet::CLI->new();
    return $cli->handle->uuid;
}

sub database_uuid {
    my $self = shift;
    my $cli  = Prophet::CLI->new();
    return $cli->handle->db_uuid;
}

=head2 replica_merge_tickets

Returns a hash of key-value pairs of the form 

 { uuid => revno,
   uuid => revno,  
}

=cut

sub replica_merge_tickets {
    my $self    = shift;
    my $cli     = Prophet::CLI->new();
    my $tickets = Prophet::Collection->new( handle => $cli->handle, type => $Prophet::Replica::MERGETICKET_METATYPE );
    $tickets->matching( sub {1} );
    return { map { $_->uuid => $_->prop('last-changeset') } $tickets->items };

}

sub replica_last_rev {
    my $cli = Prophet::CLI->new();
    return $cli->handle->latest_sequence_no;
}

=head2 as_user USERNAME CODEREF

Run this code block as USERNAME.  This routine sets up the %ENV hash so that when we go looking for a repository, we get the user's repo.

=cut

our %REPLICA_UUIDS;
our %DATABASE_UUIDS;

sub as_user {
    my $username = shift;
    my $coderef  = shift;
    local $ENV{'PROPHET_USER'} = $username;
    local $ENV{'PROPHET_REPO'} = repo_path_for($username);

    my $ret = $coderef->();

    $REPLICA_UUIDS{$username} = replica_uuid();
    $DATABASE_UUIDS{$username} = database_uuid();

    return $ret;
}

sub replica_uuid_for {
    my $user = shift;
    return $REPLICA_UUIDS{$user};
}

sub database_uuid_for {
    my $user = shift;
    return $DATABASE_UUIDS{$user};
}

=head2 fetch_newest_changesets COUNT

Returns C<COUNT> newest L<Prophet::ChangeSet> objects in the current user's replica.

=cut

sub fetch_newest_changesets {
    my $count = shift;
    my $source = Prophet::Replica->new( { url => repo_uri_for( $ENV{'PROPHET_USER'} ) } );
    return @{ $source->fetch_changesets( after => ( replica_last_rev() - $count ) ) };

}

=head2 ensure_new_revisions { CODE }, $numbers_of_new_revisions, $msg

=cut

sub ok_added_revisions (&$$) {
    my ( $code, $num, $msg ) = @_;
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    my $last_rev = replica_last_rev();
    $code->();
    is( replica_last_rev(), $last_rev + $num, $msg );
}

=head2 serialize_conflict Prophet::Conflict

returns a simple, serialized version of a Prophet::Conflict object suitable for comparison in tests

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

sub serialize_changeset {
    my $cs = shift;

    return $cs->as_hash;
}

=head2 run_command arguments -> stdout

Run the given command using a new L<Prophet::CLI> object. Returns the standard
output of that command.

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

    sub load_record {
        my $type = shift;
        my $uuid = shift;

        my $record = Prophet::Record->new(handle => $connection, type => $type);
        $record->load(uuid => $uuid);
        return $record;
    }
}

=head2 as_alice CODE, as_bob CODE, as_charlie CODE, as_david CODE

Runs CODE as alice, bob, charlie or david


=cut

sub as_alice (&)  { as_user( alice   => shift ) }
sub as_bob (&)    { as_user( bob     => shift ) }
sub as_charlie(&) { as_user( charlie => shift ) }
sub as_david(&)   { as_user( david   => shift ) }

END {
    for (qw(alice bob charlie david)) {

        #     as_user( $_, sub { rmtree [ $ENV{'PROPHET_REPO'} ] } );
    }
}

1;
