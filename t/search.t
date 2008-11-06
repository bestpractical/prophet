#!/usr/bin/env perl
use strict;
use warnings;
use Prophet::Test tests => 16;

as_alice {
    run_ok('prophet', [qw(init)], "created a db as alice");
    run_ok('prophet', [qw(create --type=Bug --), 'summary=first ticket summary', 'status=new'], "created a record as alice");
    run_ok('prophet', [qw(create --type=Bug --), 'summary=other ticket summary', 'status=open'], "created a record as alice");
    run_ok('prophet', [qw(create --type=Bug --), 'summary=bad ticket summary', 'status=stalled', 'cmp=ne'], "created a record as alice");

    run_output_matches('prophet', [qw(search --type Bug --regex .)],
        [qr/first ticket summary/,
         qr/other ticket summary/,
         qr/bad ticket summary/],
        "Found our records",
    );

    run_output_matches('prophet', [qw(ls --type Bug -- status=new)],
        [qr/first ticket summary/],
        "found the only ticket with status=new",
    );

    run_output_matches('prophet', [qw(search --type Bug -- status=open)],
        [qr/other ticket summary/],
        "found the only ticket with status=open",
    );

    run_output_matches('prophet', [qw(search --type Bug -- status=closed)],
        [],
        "found no tickets with status=closed",
    );

    run_output_matches('prophet', [qw(search --type Bug -- status=new status=open)],
        [qr/first ticket summary/, qr/other ticket summary/],
        "found two tickets with status=new OR status=open",
    );

    run_output_matches('prophet', [qw(search --type Bug -- status!=new)],
        [qr/other ticket summary/, qr/bad ticket summary/],
        "found two tickets with status!=new",
    );

    run_output_matches('prophet', [qw(search --type Bug -- status=~n)],
        [qr/first ticket summary/, qr/other ticket summary/],
        "found two tickets with status=~n",
    );

    run_output_matches('prophet', [qw(search --type Bug -- summary=~first|bad)],
        [qr/first ticket summary/, qr/bad ticket summary/],
        "found two tickets with status=~first|stalled",
    );

    run_output_matches('prophet', [qw(search --type Bug -- status !=new summary=~first|bad)],
        [qr/bad ticket summary/],
        "found two tickets with status=~first|bad",
    );

    run_output_matches('prophet', [qw(search --type Bug -- status ne new summary =~ first|bad)],
        [qr/bad ticket summary/],
        "found two tickets with status=~first|bad",
    );

    run_output_matches('prophet', [qw(search --type Bug -- cmp ne)],
        [qr/bad ticket summary/],
        "found the ticket with cmp=ne (which didn't treat 'ne' as a comparator)",
    );

    run_output_matches('prophet', [qw(search --type Bug --regex=new -- status=~n)],
        [qr/first ticket summary/],
        "found a ticket with regex and props working together",
    );
};

