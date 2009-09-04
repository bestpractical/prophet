#!/usr/bin/perl -w
use strict;

use Prophet::Test tests => 4;

BEGIN {
    require File::Temp;
    $ENV{'PROPHET_REPO'} = File::Temp::tempdir(
        CLEANUP => ! $ENV{PROPHET_DEBUG}  ) . '/repo-' . $$;
    diag $ENV{'PROPHET_REPO'};
}

# regression test: bad things happen when you're allowed to e.g., update
# a record of type comment when your context's type is set to ticket

run_command( 'init', '--non-interactive' );

my ($ticket_id, $ticket_uuid)
    = (run_command( qw(create --type ticket -- status=new) )
            =~ qr/Created ticket (\d+) \((\S+)\)/);

ok( $ticket_uuid, "Created ticket record $ticket_id" );

my ($comment_id, $comment_uuid)
    = (run_command( qw(create --type comment -- content="yay!") )
            =~ qr/Created comment (\d+) \((\S+)\)/);

ok( $comment_uuid, "Created comment record $comment_id" );

my ($output, $error)
    = (run_command( qw(update --type ticket --id), $comment_id,
            qw(-- status=closed) ) );

like( $error, qr/couldn't find a ticket with that id/,
    "Couldn't update comment record as ticket type" );

($output, $error) = run_command( qw(show --type ticket --id), $comment_uuid );
like( $error, qr/couldn't find a ticket with that id/,
    "Couldn't show ticket with comment's uuid" );
