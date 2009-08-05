#!/usr/bin/perl 
#
use warnings;
use strict;

use Prophet::Test tests => 24;

as_alice {
    ok( run_command( 'init' ), 'alice replica init' );
    ok( run_command( qw(create --type Bug -- --status new --from alice )),
        'Created a record as alice' );
    my $output = run_command( qw(search --type Bug --regex .) );
    like( $output, qr/new/, 'Found our record' );

    # update the record
    # show the record history
    # show the record
};

as_bob {
    ok( run_command( qw(init) ), 'bob replica init' );
    ok( run_command( qw(create --type Bug -- --status open --from bob ) ),
        'Created a record as bob' );
    my $output = run_command( qw(search --type Bug --regex .) );
    like( $output, qr/open/, 'Found our record' );

    # update the record
    # show the record history
    # show the record
};

as_alice {
    # sync from bob
    diag('Alice syncs from bob');
    ok( run_command(
            'merge',  '--from', repo_uri_for('bob'),
            '--to', repo_uri_for('alice'), '--force',
        ), 'Sync ran ok!' );

    # check our local replicas
    my $out = run_command( qw(search --type Bug --regex .) );
    like( $out, qr/open/ );
    like( $out, qr/new/ );
    my @out = split( /\n/, $out );
    is( scalar @out, 2, "We found only two rows of output" );

    my $last_rev = replica_last_rev();

    diag('Alice syncs from bob again. There will be no new changes from bob');

    # sync from bob
    ok( run_command(
            'merge',  '--from', repo_uri_for('bob'),
            '--to', repo_uri_for('alice'), '--force',
        ), 'Sync ran ok!' );

    # check our local replicas
    $out = run_command(  qw(search --type Bug --regex .) );
    like( $out, qr/open/ );
    like( $out, qr/new/ );
    @out = split( /\n/, $out );
    is( scalar @out, 2, "We found only two rows of output" );

    is( replica_last_rev(), $last_rev, "We have not recorded another transaction" );

};

diag('Bob syncs from alice');

as_bob {
    my $last_rev = replica_last_rev();

    my $out = run_command( qw(search --type Bug --regex .) );
    unlike( $out, qr/new/, "bob doesn't have alice's yet" );

    # sync from alice
    ok( run_command(
            'merge',  '--to', repo_uri_for('bob'),
            '--from', repo_uri_for('alice'), '--force',
        ), 'Sync ran ok!' );

    # check our local replicas
    $out = run_command( qw(search --type Bug --regex .) );
    like( $out, qr/open/ );
    like( $out, qr/new/ );
    is( replica_last_rev, $last_rev + 1, "only one rev from alice is sycned" );

   # last rev of alice is originated from bob (us), so not synced to bob, hence the merge ticket is at the previous rev.
    $last_rev = replica_last_rev();

    diag('Sync from alice to bob again');
    ok( run_command(
            'merge',  '--to', repo_uri_for('bob'),
            '--from', repo_uri_for('alice'), '--force',
        ), 'Sync ran ok!' );

    is( replica_last_rev(), $last_rev, "We have not recorded another transaction after a second sync" );

};

as_alice {
    my $last_rev = replica_last_rev();
    ok( run_command(
            'merge',  '--to', repo_uri_for('alice'),
            '--from', repo_uri_for('bob'), '--force',
        ), 'Sync ran ok!' );

    is( replica_last_rev(), $last_rev,
        "We have not recorded another transaction after bob had fully synced from alice" );
}

# create 1 record
# search for the record
#
# clone the replica to a second replica
# compare the second replica to the first replica
#   search
#   record history
#   record basics
#
# update the first replica
# merge the first replica to the second replica
#   does record history on the second replica reflect the first replica

# merge the second replica to the first replica
# ensure that no new transactions aside from a merge ticket are added to the first replica

# update the second replica
# merge the second replica to the first replica
# make sure that the first replica has the change from the second replica
#
#
# TODO: this doesn't test conflict resolution at all
# TODO: this doesn't peer to peer sync at all
