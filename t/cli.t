#!/usr/bin/perl
use warnings;
use strict;
use Prophet::Test tests => 9;

as_alice {
    run_command(qw(init));
    like(run_command(qw(create --type Bug -- --status new --from alice)), qr/Created Bug/, "Created a record as alice");

    like(run_command(qw(show 1 --type Bug --batch)), qr/id: 1/, "'show 1' dwims");
    like(run_command(qw(display 1 --type Bug --batch)), qr/id: 1/, "'display 1' dwims");

    like(run_command(qw(update 1 --type Bug --batch -- status=open)),
        qr/Bug 1 \(.+\) updated/, "'update 1' dwims");
    like(run_command(qw(edit 1 --type Bug --batch -- status=new)),
        qr/Bug 1 \(.+\) updated/, "'edit 1' dwims");

    like(run_command(qw(history 1 --type Bug --batch)), qr/^ alice\@example.com/, "'history 1' dwims");

    like(run_command(qw(delete 1 --type Bug --batch)), qr/Bug (.+) deleted/, "'delete 1' dwims");
    run_command(qw(create --type Bug -- --status new --from alice));
    like(run_command(qw(del 2 --type Bug --batch)), qr/Bug (.+) deleted/, "'del 2' dwims");
    run_command(qw(create --type Bug -- --status new --from alice));
    like(run_command(qw(rm 3 --type Bug --batch)), qr/Bug (.+) deleted/, "'rm 3' dwims");

};
