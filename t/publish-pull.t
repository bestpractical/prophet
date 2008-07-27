#!/usr/bin/perl
use warnings;
use strict;
use Prophet::Test tests => 10;
use Test::Exception;
use File::Temp 'tempdir';
use Path::Class;

my $alice_published = tempdir(CLEANUP => 1);

as_alice {
    run_ok( 'prophet', [qw(create --type Bug -- --status new --from alice )], "Created a record as alice" );
    run_output_matches( 'prophet', [qw(search --type Bug --regex .)], [qr/new/], " Found our record" );

    run_ok( 'prophet', [qw(publish --to), $alice_published] );
};

my $alice_uuid = database_uuid_for('alice');
my $path = dir($alice_published)->file($alice_uuid);

as_bob {
    run_ok( 'prophet', ['pull', '--from', "file:$path", '--force'] );
    run_output_matches( 'prophet', [qw(search --type Bug --regex .)], [qr/new/], " Found our record" );
    run_ok( 'prophet', ['pull', '--all', '--force'] );
    run_output_matches( 'prophet', [qw(search --type Bug --regex .)], [qr/new/], " Found our record" );
};

# see if uuid intuition works
# e.g. I hand you a url, http://sartak.org/misc/sd, and Prophet figures out
# that you really want http://sartak.org/misc/sd/DATABASE-UUID
as_charlie {
    my $cli  = Prophet::CLI->new();
    $cli->app_handle->handle->set_db_uuid($alice_uuid);

    run_ok( 'prophet', ['pull', '--from', "file:$alice_published", '--force'] );
    run_output_matches( 'prophet', [qw(search --type Bug --regex .)], [qr/new/], "publish database uuid intuition works" );
};

as_david {
    run_ok( 'prophet', ['pull', '--from', "file:$path"] );
};

is(database_uuid_for('alice'), database_uuid_for('david'), "pull propagated the database uuid properly");
isnt(replica_uuid_for('alice'), replica_uuid_for('david'), "pull created a new replica uuid");
