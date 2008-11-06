#!/usr/bin/perl
use warnings;
use strict;
use Prophet::Test tests => 13;
use Test::Exception;
use File::Temp 'tempdir';
use Path::Class;
use Params::Validate;

my ($bug_uuid, $pullall_uuid);

my $alice_published = tempdir(CLEANUP => 1);

as_alice {
    run_ok('prophet', [qw(init)]);
    run_output_matches( 'prophet',
        [qw(create --type Bug -- --status new --from alice --summary), 'this is a template test'],
        [qr/Created Bug \d+ \((\S+)\)(?{ $bug_uuid = $1 })/],
        "Created a Bug record as alice");
    ok($bug_uuid, "got a uuid for the Bug record");
    run_output_matches( 'prophet', [qw(search --type Bug --regex .)], [qr/new/], " Found our record" );

    run_ok( 'prophet', [qw(publish --html --to), $alice_published] );
};

my $dir = dir($alice_published);

my $merge_tickets = $dir->subdir('_merge_tickets');
ok(!-e $merge_tickets, "_merge_tickets template directory absent");

my $bug = $dir->subdir('Bug');
ok(-e $bug, "Bug template directory exists");

my $index = $bug->file('index.html');
ok(-e $index, "Bug/index.html exists");

my $bug_template = $bug->file("$bug_uuid.html");
ok(-e $bug_template, "Bug/$bug_uuid.html exists");

my $index_contents = $index->slurp;
like($index_contents, qr/$bug_uuid/, "index contains bug uuid");
like($index_contents, qr/this is a template test/, "index contains bug summary");

my $bug_contents = $bug_template->slurp;
like($bug_contents, qr/$bug_uuid/, "bug contains bug uuid");
like($bug_contents, qr/this is a template test/, "bug contains bug summary");

