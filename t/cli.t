#!/usr/bin/perl 
#
use warnings;
use strict;

use Prophet::Test tests => 19;

use_ok('Prophet::CLI');

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
    # check our local replicas
    my ($ret, $out, $err) = run_script('prophet-node-search', [qw(--type Bug --regex .)]);
    like($out, qr/open/) ;
    like($out, qr/new/) ;
    my @out = split(/\n/,$out);
    is (scalar @out, 2, "We found only two rows of output");
    
    my $cli = Prophet::CLI->new();
    isa_ok($cli->handle, 'Prophet::Handle');

    my $last_rev = $cli->handle->repo_handle->fs->youngest_rev;

    diag("Rerun the exact same sync operation. we should still only end up with two records and NO new transactions");

    # sync from bob
    run_ok('prophet-merge', ['--from', Prophet::Test::repo_uri_for('bob'), '--to', Prophet::Test::repo_uri_for('alice')], "Sync ran ok!");
    # check our local replicas
    ($ret, $out, $err) = run_script('prophet-node-search', [qw(--type Bug --regex .)]);
    like($out, qr/open/) ;
    like($out, qr/new/) ;
    @out = split(/\n/,$out);
    is (scalar @out, 2, "We found only two rows of output");

    is( $cli->handle->repo_handle->fs->youngest_rev, $last_rev, "We have not recorded another transaction");
    
};




as_bob {
    my ($ret, $out, $err) = run_script('prophet-node-search', [qw(--type Bug --regex .)]);
    unlike($out, qr/new/, "bob doesn't have alice's yet") ;

    # sync from bob
    run_ok('prophet-merge', ['--to', Prophet::Test::repo_uri_for('bob'), '--from', Prophet::Test::repo_uri_for('alice')], "Sync ran ok!");
    # check our local replicas
    ($ret, $out, $err) = run_script('prophet-node-search', [qw(--type Bug --regex .)]);
    like($out, qr/open/) ;
    like($out, qr/new/) ;
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
