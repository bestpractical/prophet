#!/usr/bin/env perl
use warnings;
use strict;
use Prophet::Test tests => 3;

# you need to run this test script from the BTDT directory

eval 'use BTDT::Test; 1;'
    or plan skip_all => 'requires 3.7 to run tests.'.$@;

my $server = BTDT::Test->make_server;
my $URL = $server->started_ok;

ok(1, "Loaded the test script");

my $GOODUSER = BTDT::CurrentUser->new( email => 'gooduser@example.com' );
my $task = BTDT::Model::Task->new(current_user => $GOODUSER);
$task->create(
    summary => "Fly Man",
    description => '',
);

diag $task->id;
my ($ret, $out, $err);

my $sd_rt_url = "hiveminder:$URL";

($ret, $out, $err) = run_script('sd', ['pull', $sd_rt_url]);
diag $err;

my ($yatta_uuid, $flyman_uuid);
run_output_matches('sd', ['ticket', '--list', '--regex', '.'], [qr/(.*?)(?{ $flyman_uuid = $1 }) Fly Man (.*)/]);
