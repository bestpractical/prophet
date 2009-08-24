#!/usr/bin/env perl
use strict;
use warnings;
use Prophet::Test tests => 18;
use Prophet::Util;

use_ok('Prophet::CLI::Command::Search');

as_alice {
    ok( run_command( 'init' ), 'created a db as alice' );
    ok( run_command(
            qw(create --type=Bug --),
            'summary=first ticket summary',
            'status=new',
        ), 'created a record as alice');
    ok( run_command(
            qw(create --type=Bug --),
            'summary=other ticket summary',
            'status=open'),
        'created a record as alice' );
    ok( run_command(
            qw(create --type=Bug --), 'summary=bad ticket summary',
            'status=stalled', 'cmp=ne',
        ), 'created a record as alice');

    my $out = run_command( qw(search --type Bug --regex .));
    my $expected = qr/.*first ticket summary.*
.*other ticket summary.*
.*bad ticket summary.*
/;
    like( $out, $expected, 'Found our records' );

    $out = run_command( qw(ls --type Bug -- status=new));
    $expected = qr/.*first ticket summary.*/;
    like( $out, $expected, 'found the only ticket with status=new' );
    $out = run_command(qw(search --type Bug -- status=open));
    $expected = qr/.*other ticket summary.*/;
    like( $out, $expected, 'found the only ticket with status=open' );

    $out = run_command( qw(search --type Bug -- status=closed));
    $expected = '';
    is( $out, $expected, 'found no tickets with status=closed' );

    $out = run_command(qw(search --type Bug -- status=new status=open));
    $expected = qr/.*first ticket summary.*
.*other ticket summary.*
/;
    like( $out, $expected, 'found two tickets with status=new OR status=open' );

    $out = run_command(qw(search --type Bug -- status!=new));
    $expected = qr/.*other ticket summary.*
.*bad ticket summary.*
/;
    like( $out, $expected, 'found two tickets with status!=new' );

    $out = run_command(qw(search --type Bug -- status=~n));
    $expected = qr/.*first ticket summary.*
.*other ticket summary.*
/;
    like( $out, $expected, 'found two tickets with status=~n' );

    $out = run_command(qw(search --type Bug -- summary=~first|bad));
    $expected = qr/.*first ticket summary.*
.*bad ticket summary.*
/;
    like( $out, $expected, 'found two tickets with status=~first|stalled' );

    $out = run_command(qw(search --type Bug -- status !=new summary=~first|bad));
    $expected = qr/bad ticket summary/;
    like( $out, $expected, 'found two tickets with status=~first|bad' );

    $out = run_command(qw(search --type Bug -- status ne new summary =~ first|bad));
    $expected = qr/bad ticket summary/;
    like( $out, $expected, 'found two tickets with status=~first|bad' );

    $out = run_command(qw(search --type Bug -- cmp ne));
    $expected = qr/bad ticket summary/;
    like( $out, $expected,
        "found the ticket with cmp=ne (which didn't treat 'ne' as a comparator)",
    );

    $out = run_command(qw(search --type Bug --regex=new -- status=~n));
    $expected = qr/first ticket summary/;
    like( $out, $expected, 'found a ticket with regex and props working together' );

    my $broken_config_content = <<'END_CONFIG';
[Bug]
    summary-format = %,status
END_CONFIG
    Prophet::Util->write_file( file => $ENV{PROPHET_APP_CONFIG},
        content => $broken_config_content );
    my $expected_error = qr/Error: cannot format value 'new' using atom '%' in 'Bug' summary format

Check that the Bug.summary-format config variable in your config
file is valid. If this variable is not set, this is a bug in the default
summary format for this ticket type.

The error encountered was:

'Invalid conversion in sprintf: end of string at/;
     my (undef, $error) = run_command( qw(search --type Bug --regex .) );
     like( $error, $expected_error, 'error on bad format atom' );
};

