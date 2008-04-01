use strict;
use warnings;
package Prophet::Test;
use base qw/Test::More Exporter/;
our @EXPORT = qw/as_alice as_bob as_charlie as_david as_user run_ok repo_uri_for run_script run_output_matches replica_last_rev replica_merge_tickets replica_uuid_for fetch_newest_changesets ok_added_revisions
serialize_conflict serialize_changeset
/;

use File::Path 'rmtree';
use File::Temp qw/tempdir/;
use Path::Class 'dir';
use Test::Exception;
use IPC::Run3 'run3';
use Params::Validate ':all';

use Prophet::CLI;


our $REPO_BASE = File::Temp::tempdir();
Test::More->import;
diag($REPO_BASE);

sub import_extra {
    my $class = shift;
    my $args  = shift;

    Test::More->export_to_level(2);

    # Now, clobber Test::Builder::plan (if we got given a plan) so we
    # don't try to spit one out *again* later
    if ($class->builder->has_plan) {
        no warnings 'redefine';
        *Test::Builder::plan = sub {};
    }
}


{ no warnings 'redefine';
sub Test::More::diag { # bad bad bad # convenient convenient convenient
   # my $tb = Test::More->builder;

Test::More->builder->diag(@_) if ( $Test::Harness::Verbose || $ENV{'TEST_VERBOSE'});
}
}

=head2 run_script SCRIPT_NAME [@ARGS]

Runs the script SCRIPT_NAME as a perl script, setting the @INC to the same as our caller

=cut


sub run_script {
    my $script = shift;
    my $args = shift || [];
    my ($stdout, $stderr);
    my @cmd = _get_perl_cmd($script);
#    diag(join(' ', @cmd, @$args));
    my $ret = run3 [@cmd, @$args], undef, \$stdout, \$stderr;
    Carp::croak $stderr if $?;
    #Test::More::diag $stderr;
    return($ret, $stdout, $stderr);
}

=head2 run_ok SCRIPT_NAME [@ARGS] (<- optional hashref), optional message

Runs the script, checking that it didn't error out.

=cut

sub run_ok {
   my $script = shift;
   my $args = shift if (ref $_[0] eq 'ARRAY');
   my $msg = shift if (@_);
   
   @_ = sub {
   
      my ($ret, $stdout,$stderr) = (run_script($script, $args), $msg);
      @_ = ($ret,$msg);
      goto &Test::More::ok;
};
    goto \&lives_and;
}

sub _mk_cmp_closure {
    my ($exp, $err) = @_;
    my $line = 0;
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
	    unless ref($item) ? ($output =~ m/$item/)
                       	      : ($output eq $item);
    }
}


=head2 is_script_output SCRIPTNAME \@ARGS, \@STDOUT_MATCH, \@STDERR_MATCH, $MSG

Runs the script, checking to see that its output matches



=cut

sub _get_perl_cmd {
    my $script = shift;
    my @cmd = ($^X, (map { "-I$_" } @INC));
    push @cmd, '-MDevel::Cover' if $INC{'Devel/Cover.pm'};
    push @cmd, 'bin/'.$script;
    return @cmd;
}

sub is_script_output {
    my ($script, $arg, $exp_stdout, $exp_stderr, $msg) = @_;
    my $stdout_err = [];
    $exp_stderr ||= [];
    my @cmd = _get_perl_cmd($script);

    my $ret = run3 [@cmd, @$arg], undef,
	_mk_cmp_closure($exp_stdout, $stdout_err), # stdout
	_mk_cmp_closure($exp_stderr, $stdout_err); # stderr
	
    if (@$stdout_err) {
    	@_ = (0, join(' ', "$msg:", $script, @$arg));
	   diag("Different in line: ".join(',', @$stdout_err));
    	goto \&ok;
    }
    else {
    	@_ = (1, join(' ', "$msg:", $script, @$arg));
    	goto \&ok;
    }

};

sub run_output_matches {
    my ($script, $args, $expected, $msg) = @_;
    lives_and {
        @_ = ($script, $args, $expected, [], $msg);
        goto \&is_script_output;
    };
    

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

use constant IS_WIN32 => ($^O eq 'MSWin32');

sub repo_uri_for {
    my $username = shift;    
    
    my $path = repo_path_for($username);
    $path =~ s{^|\\}{/}g if IS_WIN32;

    return 'file://'.$path;
}


sub replica_uuid {
    my $self = shift;
    my $cli = Prophet::CLI->new();
    return $cli->handle->uuid;   
}

=head2 replica_merge_tickets

Returns a hash of key-value pairs of the form 

 { uuid => revno,
   uuid => revno,  
}

=cut

sub replica_merge_tickets {
  my $self = shift;
  my $cli = Prophet::CLI->new();
  my $tickets = Prophet::Collection->new(handle => $cli->handle, type => $Prophet::Handle::MERGETICKET_METATYPE);  
  $tickets->matching(sub { 1 });
  return { map {  $_->uuid => $_->prop('last-changeset') } @{$tickets->as_array_ref} };

}

sub replica_last_rev {
    my $cli = Prophet::CLI->new();
    return $cli->handle->repo_handle->fs->youngest_rev;
}


=head2 as_user USERNAME CODEREF

Run this code block as USERNAME.  This routine sets up the %ENV hash so that when we go looking for a repository, we get the user's repo.

=cut

our %REPLICA_UUIDS;

sub as_user {
  my $username = shift;
  my $coderef = shift;
  local $ENV{'PROPHET_USER'} = $username;
  local $ENV{'PROPHET_REPO'} = repo_path_for($username);
#  diag("I am $username. My replica id is ".replica_uuid());
 my $ret=  $coderef->();
 $REPLICA_UUIDS{$username} = replica_uuid();
 return $ret;
}


sub replica_uuid_for {
    my $user = shift;
    return $REPLICA_UUIDS{$user};

}

=head2 fetch_newest_changesets COUNT

Returns C<COUNT> newest L<Prophet::ChangeSet> objects in the current user's replica.

=cut

sub fetch_newest_changesets {
    my $count = shift;
    my $source = Prophet::Sync::Source->new( { url => repo_uri_for($ENV{'PROPHET_USER'})} );
    return @{$source->fetch_changesets( after => (replica_last_rev() - $count))};


}


=head2 ensure_new_revisions { CODE }, $numbers_of_new_revisions, $msg

=cut

sub ok_added_revisions (&$$) {
    my ($code, $num, $msg) = @_;
    my $last_rev = replica_last_rev();
    $code->();    
    is( replica_last_rev(), $last_rev + $num, $msg );
}



=head2 serialize_conflict Prophet::Conflict

returns a simple, serialized version of a Prophet::Conflict object suitable for comparison in tests

=cut

sub serialize_conflict {
    my ($conflict_obj) = validate_pos(@_, { isa => 'Prophet::Conflict'});    
    my $conflicts;
    for my $change ( @{$conflict_obj->conflicting_changes} ) {
        $conflicts->{meta} = { original_source_uuid => $conflict_obj->changeset->original_source_uuid};
        $conflicts->{records}->{$change->node_uuid} =  {
                change_type => $change->change_type,
                };

        for my $propchange (@{$change->prop_conflicts}) {
             $conflicts->{records}->{$change->node_uuid}->{props}->{$propchange->name} = { source_old => $propchange->source_old_value,
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
    
    

=head2 as_alice CODE, as_bob CODE, as_charlie CODE, as_david CODE

Runs CODE as alice, bob, charlie or david


=cut

sub as_alice (&) { as_user( alice => shift) }
sub as_bob (&){ as_user( bob => shift) }
sub as_charlie(&) { as_user( charlie => shift) }
sub as_david(&) { as_user( david => shift) }

END {
    for (qw(alice bob charlie david)) {
   #     as_user( $_, sub { rmtree [ $ENV{'PROPHET_REPO'} ] } );
    }
}


1;
