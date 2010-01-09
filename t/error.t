#!/usr/bin/perl
use warnings;
use strict;

use Prophet::Test tests => 2;
use File::Temp qw(tempdir);

$ENV{'PROPHET_REPO'} = tempdir( CLEANUP => ! $ENV{PROPHET_DEBUG}  ) . '/repo-' . $$;
diag "Replica is in $ENV{PROPHET_REPO}";

# testing various error conditions that don't make sense to test anywhere else

my $no_replica = tempdir( CLEANUP => ! $ENV{PROPHET_DEBUG}  ) . '/repo-' . $$;
my @cmds = (
    {
        cmd     => [ 'push', '--to', $no_replica ],
        error   => [
            "No replica found at '$no_replica'.",
            ],
        comment => 'push to nonexistant replica',
    },
    {
        cmd     => [ 'push', '--to', 'http://foo.com/bar' ],
        error   => [
            "Can't push to HTTP replicas! You probably want to publish"
            ." instead.",
            ],
        comment => 'push to HTTP replica',
    },
);

for my $item ( @cmds ) {
    my $exp_error
        = defined $item->{error}
        ? (join "\n", @{$item->{error}}) . "\n"
        : '';
    my ($got_output, $got_error) = run_command( @{$item->{cmd}} );
    is( $got_error, $exp_error, $item->{comment} );
}
