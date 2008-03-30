package Prophet::Test;
use strict;
use base qw/Test::More Exporter/;
our @EXPORT = qw/as_alice as_bob as_charlie as_david run_ok run_output_matches/;

use File::Temp qw/tempdir/;
use Path::Class 'dir';
use Test::Exception;


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

=head2 run_script SCRIPT_NAME [@ARGS]

Runs the script SCRIPT_NAME as a perl script, setting the @INC to the same as our caller

=cut


sub run_script {
    my $script = shift;
    system($^X, (map { "-I$_" } @INC), 'bin/'.$script, @_);
    Carp::croak $! if $?;
    return;
}

=head2 run_ok SCRIPT_NAME [@ARGS] (<- optional hashref), optional message

Runs the script, checking that it didn't error out.

=cut

sub run_ok {
   my $script = shift;
   my $args = shift if (ref $_[0] eq 'ARRAY');
   my $msg = shift if (@_);
   
   lives_and {
   
      @_ = (run_script($script, @$args), $msg);
      goto &Test::More::ok;
};
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

use IPC::Run3 'run3';

=head2 is_script_output SCRIPTNAME \@ARGS, \@STDOUT_MATCH, \@STDERR_MATCH, $MSG

Runs the script, checking to see that its output matches



=cut

sub is_script_output {
    my ($script, $arg, $exp_stdout, $exp_stderr, $msg) = @_;
    my $stdout_err = [];
    $exp_stderr ||= [];
    my @cmd = ($^X, (map { "-I$_" } @INC), 'bin/'.$script);

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

=head2 as_user USERNAME CODEREF

Run this code block as USERNAME.  This routine sets up the %ENV hash so that when we go looking for a repository, we get the user's repo.

=cut

sub as_user {
  my $username = shift;
  my $coderef = shift;

  local $ENV{'PROPHET_REPO'} = repo_path_for($username);
 $coderef->();
}



=head2 as_alice CODE, as_bob CODE, as_charlie CODE, as_david CODE

Runs CODE as alice, bob, charlie or david


=cut

sub as_alice (&) { as_user( alice => shift) }
sub as_bob (&){ as_user( bob => shift) }
sub as_charlie(&) { as_user( charlie => shift) }
sub as_david(&) { as_user( david => shift) }

use File::Path 'rmtree';
END {
    for (qw(alice bob charlie david)) {
        as_user( $_, sub { rmtree [ $ENV{'PROPHET_REPO'} ] } );
    }
}


1;
