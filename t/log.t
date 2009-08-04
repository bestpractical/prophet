use warnings;
use strict;
use Prophet::Test tests => 22;
use File::Temp qw'tempdir';

# tests for log command

use_ok('Prophet::CLI');
$ENV{'PROPHET_REPO'} = tempdir( CLEANUP => ! $ENV{PROPHET_DEBUG}  ) . '/repo-' . $$;

my $cli = Prophet::CLI->new();
my $handle = $cli->handle;

isa_ok( $handle, 'Prophet::Replica', "Got the handle" );

$handle->initialize;

use_ok('Prophet::CLI::Command::Log');

# make some changes so the tests below don't pass just because they always
# get zero as the latest sequence number
use_ok('Prophet::Record');
my $record = Prophet::Record->new( handle => $handle, type => 'Person' );
my $mao = $record->create( props => { name => 'Mao', age => 0.7, species => 'cat' } );
$record->set_prop( name => 'age', value => 1 );
$record->set_prop( name => 'color', value => 'black' );

diag("latest sequence no is ".$handle->latest_sequence_no);

# test the range parsing / setting
my $log = new Prophet::CLI::Command::Log(handle => $handle, cli => $cli, context => $cli->context );

$log->set_arg('range', '0..20');
my ($start, $end) = $log->parse_range_arg();
is($start, 0, '0..20 starts at 0');
is($end, 20, '0..20 ends at 20');

$log->set_arg('range', '0..LATEST~5');
($start, $end) = $log->parse_range_arg();
is($start, 0, '0..LATEST~5 starts at 0');
is($end, $handle->latest_sequence_no - 5,
    '0..LATEST~5 ends at latest changeset - 5');

$log->set_arg('range', 'LATEST~8..50');
($start, $end) = $log->parse_range_arg();
is($start, $handle->latest_sequence_no - 8, 'LATEST~8..50 starts at latest - 8');
is($end, 50, 'LATEST~8..50 ends at 50');

$log->set_arg('range', 'LATEST~10..LATEST~5');
($start, $end) = $log->parse_range_arg();
is($start, $handle->latest_sequence_no - 10, 'LATEST~10..LATEST~5 starts at latest - 10');
is($end, $handle->latest_sequence_no - 5, 'LATEST~10..LATEST~5 ends at latest - 5');

$log->set_arg('range', 'LATEST~10');
($start, $end) = $log->parse_range_arg();
is($start, $handle->latest_sequence_no - 10, 'LATEST~10 starts at latest - 10');
is($end, $handle->latest_sequence_no, 'LATEST~10 ends at latest');

$log->set_arg('range', 'LATEST');
($start, $end) = $log->parse_range_arg();
is($start, $handle->latest_sequence_no, 'LATEST starts at latest');
is($end, $handle->latest_sequence_no, 'LATEST ends at latest');

# run the command and test its output

my $replica_uuid = replica_uuid;
my $first = " $ENV{PROPHET_EMAIL}".' at \d{4}-\d{2}-\d{2} .+	\(1\@'.$replica_uuid.'\)
 # Person 1 \(\w{8}-\w{4}-\w{4}-\w{4}-\w{12}\)
  \+ "age" set to "0.7"
  \+ "creator" set to "'.$ENV{PROPHET_EMAIL}.'"
  \+ "name" set to "Mao"
  \+ "original_replica" set to "'.$replica_uuid.'"
  \+ "species" set to "cat"';

my $second = " $ENV{PROPHET_EMAIL}".' at \d{4}-\d{2}-\d{2} .+	\(2\@'.$replica_uuid.'\)
 # Person 1 \(\w{8}-\w{4}-\w{4}-\w{4}-\w{12}\)
  > "age" changed from "0.7" to "1"\.';

my $third = " $ENV{PROPHET_EMAIL}".' at \d{4}-\d{2}-\d{2} .+	\(3\@'.$replica_uuid.'\)
 # Person 1 \(\w{8}-\w{4}-\w{4}-\w{4}-\w{12}\)
  \+ "color" set to "black"';

# --all
my $out = run_command('log', '--all');
like($out, qr{$third\n\n$second\n\n$first\n\n}, "--all outputs all changes");

# range: digit and LATEST
$out = run_command('log', '--range=0..LATEST~2');
like($out, qr{$first\n\n}, "just the first change");

# range: assumed end
$out = run_command('log', '--range=LATEST~2');
like($out, qr{$third\n\n$second\n\n}, "last two changes");

# syntactic sugar
$out = run_command('log', 'LATEST~2');
like($out, qr{$third\n\n$second\n\n}, "syntactic sugar doesn't change output");

# error -- invalid input
(undef, my $error) = run_command( 'log', '--range', 'invalid' );
is( $error, "Invalid range specified.\n", "invalid input caught correctly" );

# error -- end is before start
(undef, $error) = run_command( 'log', '10..5' );
is( $error, "START must be before END in START..END.\n",
    "caught START before END correctly" );
