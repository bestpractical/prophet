#!/usr/bin/perl
use warnings;
use strict;
use Prophet::Test tests => 2;

as_alice {
    like(run_command(qw(create --type Bug -- --status new --from alice)), qr/Created Bug/, "Created a record as alice");
    like(run_command(qw(show 1 --type Bug --batch)), qr/id: 1/, "'show 1' dwims");
};

