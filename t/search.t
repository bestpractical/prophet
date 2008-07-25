#!/usr/bin/env perl
use strict;
use warnings;
use Prophet::Test tests => 12;

as_alice {
    run_ok('prophet', [qw(create --type=Bug --), 'summary=first ticket summary', 'status=new'], "created a record as alice");
    run_ok('prophet', [qw(create --type=Bug --), 'summary=other ticket summary', 'status=open'], "created a record as alice");
    run_ok('prophet', [qw(create --type=Bug --), 'summary=bad ticket summary', 'status=stalled'], "created a record as alice");

    run_output_matches('prophet', [qw(search --type Bug --regex .)],
        [qr/first ticket summary/,
         qr/other ticket summary/,
         qr/bad ticket summary/],
        "Found our records",
    );

    run_output_matches('prophet', [qw(search --type Bug -- status=new)],
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

    TODO: {
        local $TODO = "props are stored in a flat hash, so we can't do OR yet";
        run_output_matches('prophet', [qw(search --type Bug -- status=new status=open)],
            [qr/first ticket summary/, qr/other ticket summary/],
            "found two tickets with status=new OR status=open",
        );
    };

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

    TODO: {
        local $TODO = "regex comparisons not implemented yet";
        run_output_matches('prophet', [qw(search --type Bug -- status !=new summary=~first|bad)],
            [qr/bad ticket summary/],
            "found two tickets with status=~first|bad",
        );
    };
};

