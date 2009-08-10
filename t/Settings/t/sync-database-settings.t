#!/usr/bin/perl 
use warnings;
use strict;

use lib 't/Settings/lib';
use App::Settings::Test tests => 12;

as_alice {
    ok( run_command( qw(init) ), 'replica init' );
    ok( run_command( qw(create --type Bug -- --status new --from alice ) ),
            'Created a record as alice' );

    my $output = run_command( qw(search --type Bug --regex .) );
    like( $output, qr/new/, 'Found our record' );

    $output = run_command( qw(settings show) );
    like( $output, qr/default_status: \["new"\]/,
        'the original milestone list is there');

    ok( run_command( qw(settings set -- default_status ["open"]) ),
        'set default_status to ["open"]' );

    $output = run_command( qw(settings --show) );
    like( $output, qr/default_status: \["open"\]/,
        'the original milestone list is there' );
};

as_bob {
    ok( run_command( 'clone', '--from', repo_uri_for('alice') ),
        'Sync ran ok!' );
    my $stdout = run_command( qw(settings show) );
    like( $stdout, qr/default_status: \["open"\]/,
        'the original milestone list is there' );
    ok( run_command( qw(settings set -- default_status ["stalled"]) ),
        'set default_status to ["stalled"]' );
    $stdout = run_command( qw(settings show) );
    like( $stdout, qr/default_status: \["stalled"\]/,
        'the original milestone list is there');
};

as_alice {
    ok( run_command( 'pull', '--from', repo_uri_for('bob') ), 'Sync ran ok!' );
    my $stdout = run_command( qw(settings show) );
    like( $stdout, qr/default_status: \["stalled"\]/,
        'the original milestone list is there' );
};
