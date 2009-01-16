use warnings;
use strict;
use Test::More tests => 13;

use File::Temp qw'tempdir';

use_ok('Prophet::CLI');
use_ok('Prophet::Record');
$ENV{'PROPHET_REPO'} = tempdir( CLEANUP => ! $ENV{PROPHET_DEBUG}  ) . '/repo-' . $$;
$ENV{'PROPHET_METADATA_DIRECTORY'} = tempdir( CLEANUP => ! $ENV{PROPHET_DEBUG}  ) . '/repo-' . $$;

my $cli = Prophet::CLI->new();
my $cxn = $cli->handle;
$cxn->initialize;

my $record = Prophet::Record->new(handle => $cxn, type => 'Empty');
my $uuid = $record->create(props => { which => 'first'});
my $luid = $record->luid;
ok($uuid, "got a uuid $uuid");
ok($luid, "got a luid $luid");

$record = Prophet::Record->new(handle => $cxn, type => 'Empty');
$record->load(uuid => $uuid);
is($record->uuid, $uuid, "load accepts a uuid");

$record = Prophet::Record->new(handle => $cxn, type => 'Empty');
$record->load(luid => $luid);
is($record->uuid, $uuid, "load accepts an luid");
is($record->luid, $luid, "same luid after load");

my $record2 = Prophet::Record->new(handle => $cxn, type => 'Empty');
my $uuid2 = $record2->create(props => { which => 'second'});
my $luid2 = $record2->luid;
isnt($uuid, $uuid2, "different uuids");
isnt($luid, $luid2, "different luids");

$record2 = Prophet::Record->new(handle => $cxn, type => 'Empty');
$record2->load(luid => $luid2);
is($record2->uuid, $uuid2, "load accepts an luid");
is($record2->luid, $luid2, "same luid after load");


# test to see if luids are stable across record edit. (This was a bug on sqlite)

$record2->set_props(props => { foo => 'bar'});

$record2 = Prophet::Record->new(handle => $cxn, type => 'Empty');
$record2->load(uuid => $uuid2);
is($record2->uuid, $uuid2, "load accepts an luid");
is($record2->luid, $luid2, "same luid after load");








