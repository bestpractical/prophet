#!/usr/bin/perl -w
use strict;
use Prophet::Test::Arena;

Prophet::Test::Arena->run_from_yaml;

__DATA__
--- 
chickens: 
  - QUEEN
  - DMR
  - MUNROER
recipe: 
  - 
    - MUNROER
    - create_record
    - 
      props: 
        - --the_Dark_Lord
        - glipp
        - --He
        - uggh
        - --the_Shadow
        - slosh
        - --the_Lord_of_the_Dark_Tower
        - bang
        - --the_Lord_of_the_Earth
        - clank_est
      result: 6
  - 
    - QUEEN
    - sync_from_peer
    - 
      from: MUNROER
  - 
    - MUNROER
    - update_record
    - 
      props: 
        the_Dark_Lord: bang
        the_Lord_of_the_Dark_Tower: slosh
        the_Shadow: glipp
      record: 6
  - 
    - QUEEN
    - update_record
    - 
      props: 
        He: clank_est
        the_Dark_Lord: bang
        the_Lord_of_the_Dark_Tower: slosh
        the_Shadow: glipp
      record: 6
  - 
    - MUNROER
    - update_record
    - 
      props: 
        He: slosh
        the_Lord_of_the_Dark_Tower: bang
        the_Ring_Maker: clunk
        the_Shadow: glipp
      record: 6
  - 
    - DMR
    - sync_from_peer
    - 
      from: QUEEN
