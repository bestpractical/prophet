package Prophet::Test;

use base qw/Test::More Exporter/;
our @EXPORT = qw/as_alice as_bob as_charlie as_david/;

use File::Temp qw/tempdir/;
use Path::Class 'dir';

our $REPO_BASE = File::Temp::tempdir();

sub import_extra {
    my $class = shift;
    my $args  = shift;

    $class->setup($args);
    Test::More->export_to_level(2);

    # Now, clobber Test::Builder::plan (if we got given a plan) so we
    # don't try to spit one out *again* later
    if ($class->builder->has_plan) {
        no warnings 'redefine';
        *Test::Builder::plan = sub {};
    }
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

as_alice (&) { as_user( alice => shift) }
as_bob (&){ as_user( bob => shift) }
as_charlie(&) { as_user( charlie => shift) }
as_david(&) { as_user( david => shift) }



1;
