#!/usr/bin/perl 
#
use warnings;
use strict;

use Prophet::Test tests => 7;
as_alice {
    run_ok('prophet-node-create', [qw(--type Bug --status new --from alice )], "Created a record as alice"); 
    run_output_matches('prophet-node-search', [qw(--type Bug --regex .)], [qr/new/], " Found our record");
    # update the node
    # show the node history
    # show the node

};


as_bob {
    run_ok('prophet-node-create', [qw(--type Bug --status open --from bob )], "Created a record as bob" );
    run_output_matches('prophet-node-search', [qw(--type Bug --regex .)], [qr/open/], " Found our record");
    # update the node
    # show the node history
    # show the node
};

as_alice {
    # sync from bob
    run_ok('prophet-merge', ['--from', Prophet::Test::repo_uri_for('bob'), '--to', Prophet::Test::repo_uri_for('alice')], "Sync ran ok!");
    # check our local replica
      my ($out, $err) = run_script('prophet-node-search', [qw(--type Bug --regex .)]);
      like_ok($out, qr/open/) ;
      like_ok($out, qr/new/) ;


};


# create 1 node
# search for the node
#
# clone the replica to a second replica
# compare the second replica to the first replica
#   search
#   node history
#   node basics
#
# update the first replica
# merge the first replica to the second replica
#   does node history on the second replica reflect the first replica

# merge the second replica to the first replica
# ensure that no new transactions aside from a merge ticket are added to the first replica


# update the second replica
# merge the second replica to the first replica
# make sure that the first replica has the change from the second replica
#
#
# TODO: this doesn't test conflict resolution at all
# TODO: this doesn't peer to peer sync at all
