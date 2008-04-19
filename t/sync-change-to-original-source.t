#!/usr/bin/perl -w
use strict;


BEGIN {
#$ENV{'PROPHET_REPLICA_TYPE'} = 'prophet';
};

use Prophet::Test::Arena;

# "This test fails when your replica doesn't properly set original source metadata"

Prophet::Test::Arena->run_from_yaml;

__DATA__
--- 
chickens: 
  - ALICE
  - BOB
recipe: 
  - 
    - ALICE
    - create_record
    - 
      props: 
        - --B
        - charlie
      result: 10
  - 
    - BOB
    - sync_from_peer
    - 
      from: ALICE
  - 
    - ALICE
    - sync_from_peer
    - 
      from: BOB
