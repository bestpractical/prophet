use warnings;
use strict;
use Prophet::Test tests => 9;
use File::Temp qw'tempdir';

# test coverage for Prophet::CLI::Command arg translation

use_ok('Prophet::CLI');
$ENV{'PROPHET_REPO'} = tempdir( CLEANUP => ! $ENV{PROPHET_DEBUG}  ) . '/repo-' . $$;

my $cli = Prophet::CLI->new();
can_ok($cli, 'app_handle');
can_ok($cli, 'handle');
my $cxn = $cli->handle;
isa_ok( $cxn, 'Prophet::Replica', "Got the cxn" );

use_ok('Prophet::CLI::Command');

my $context = $cli->context;

diag('Checking default arg translations');
$context->set_arg('a');
$context->set_arg('v');
my $command = Prophet::CLI::Command->new( handle => $cxn, context => $context );

is($command->has_arg('all'), 1, 'translation of -a to --all correct');
is($command->has_arg('verbose'), 1, 'translation of -v to --verbose correct');

use_ok('Prophet::CLI::Command::Server');
$context->set_arg( p => '8080');
my $server = Prophet::CLI::Command::Server->new( handle => $cxn, context => $context );
diag('Checking a subclass arg translation (with value)');
is($server->context->arg('port'), '8080', 'translation of -p to --port correct');
