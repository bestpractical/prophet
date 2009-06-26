#!/usr/bin/perl 
#
use warnings;
use strict;

use Prophet::Test tests => 12;
$ENV{'PERL5LIB'} .=  ':t/Settings/lib';


as_alice {
    run_ok('settings', [qw(init)]);
    run_ok( 'settings', [qw(create --type Bug -- --status new --from alice )], "Created a record as alice" );
    run_output_matches( 'settings', [qw(search --type Bug --regex .)], [qr/new/], [], "Found our record" );
    my ($return, $stdout, $stderr) = run_script('settings', [qw(settings --show)]);
    like($stdout, qr/default_status: \["new"\]/, "the original milestone list is there");
    run_ok('settings', [qw(settings --set -- default_status ["open"])]);
    ($return, $stdout, $stderr) = run_script('settings', [qw(settings --show)]);
    like($stdout, qr/default_status: \["open"\]/, "the original milestone list is there");



};
as_bob {
    run_ok( 'settings', [ 'clone', '--from', repo_uri_for('alice')], "Sync ran ok!" );
    my ($return, $stdout, $stderr) = run_script('settings', [qw(settings --show)]);
    like($stdout, qr/default_status: \["open"\]/, "the original milestone list is there");
    run_ok('settings', [qw(settings --set -- default_status ["stalled"])]);
    ($return, $stdout, $stderr) = run_script('settings', [qw(settings --show)]);
    like($stdout, qr/default_status: \["stalled"\]/, "the original milestone list is there");

};


as_alice {
    run_ok( 'settings', [ 'pull', '--from', repo_uri_for('bob') ], "Sync ran ok!" );
    my ($return, $stdout, $stderr) = run_script('settings', [qw(settings --show)]);
    like($stdout, qr/default_status: \["stalled"\]/, "the original milestone list is there");

};
