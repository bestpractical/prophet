#!/usr/bin/perl 
#
use warnings;
use strict;

use Prophet::Test tests => 3;

as_alice {
    ok(`bin/prophet-node-create --type Bug --status new` );
}

# create 1 node
# update the node
# search for the node
# show the node history
# show the node
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
