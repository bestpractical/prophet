#!/usr/bin/perl 
#
use warnings;
use strict;

use Prophet::Test tests => 27;

as_alice {
    run_ok('prophet', [qw(init)]);
    run_ok( 'prophet', [qw(create --type Bug -- --status new --from alice )], "Created a record as alice" );
    run_output_matches( 'prophet', [qw(search --type Bug --regex .)], [qr/new/], " Found our record" );

    # update the record
    # show the record history
    # show the record
};

as_bob {
    run_ok('prophet', [qw(init)]);
    run_ok( 'prophet', [qw(create --type Bug -- --status open --from bob )], "Created a record as bob" );
    run_output_matches( 'prophet', [qw(search --type Bug --regex .)], [qr/open/], " Found our record" );

    # update the record
    # show the record history
    # show the record

};

as_alice {

    # sync from bob
    diag('Alice syncs from bob');
    run_ok( 'prophet', [ 'merge',  '--from', repo_uri_for('bob'), '--to', repo_uri_for('alice'), '--force' ], "Sync ran ok!" );

    # check our local replicas
    my ( $ret, $out, $err ) = run_script( 'prophet', [qw(search --type Bug --regex .)] );
    like( $out, qr/open/ );
    like( $out, qr/new/ );
    my @out = split( /\n/, $out );
    is( scalar @out, 2, "We found only two rows of output" );

    my $last_rev = replica_last_rev();

    diag('Alice syncs from bob again. There will be no new changes from bob');

    # sync from bob
    run_ok( 'prophet', [ 'merge',  '--from', repo_uri_for('bob'), '--to', repo_uri_for('alice'), '--force' ], "Sync ran ok!" );

    # check our local replicas
    ( $ret, $out, $err ) = run_script( 'prophet', [qw(search --type Bug --regex .)] );
    like( $out, qr/open/ );
    like( $out, qr/new/ );
    @out = split( /\n/, $out );
    is( scalar @out, 2, "We found only two rows of output" );

    is( replica_last_rev(), $last_rev, "We have not recorded another transaction" );
    is_deeply( replica_merge_tickets(), { replica_uuid_for('bob') => as_bob { replica_last_rev() } } );

};

diag('Bob syncs from alice');

as_bob {
    my $last_rev = replica_last_rev();

    my ( $ret, $out, $err ) = run_script( 'prophet', [qw(search --type Bug --regex .)] );
    unlike( $out, qr/new/, "bob doesn't have alice's yet" );

    # sync from alice

    run_ok( 'prophet', [ 'merge',  '--to', repo_uri_for('bob'), '--from', repo_uri_for('alice'), '--force' ], "Sync ran ok!" );

    # check our local replicas
    ( $ret, $out, $err ) = run_script( 'prophet', [qw(search --type Bug --regex .)] );
    like( $out, qr/open/ );
    like( $out, qr/new/ );
    is( replica_last_rev, $last_rev + 1, "only one rev from alice is sycned" );

   # last rev of alice is originated from bob (us), so not synced to bob, hence the merge ticket is at the previous rev.
    is_deeply( replica_merge_tickets(), { replica_uuid_for('alice') => as_alice { replica_last_rev() - 1 } } );
    $last_rev = replica_last_rev();

    diag('Sync from alice to bob again');
    run_ok( 'prophet', [ 'merge',  '--to', repo_uri_for('bob'), '--from', repo_uri_for('alice'), '--force' ], "Sync ran ok!" );

    is_deeply( replica_merge_tickets(), { replica_uuid_for('alice') => as_alice { replica_last_rev() - 1 } } );
    is( replica_last_rev(), $last_rev, "We have not recorded another transaction after a second sync" );

};

as_alice {
    my $last_rev = replica_last_rev();
    run_ok( 'prophet', [ 'merge',  '--to', repo_uri_for('alice'), '--from', repo_uri_for('bob'), '--force' ], "Sync ran ok!" );
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
