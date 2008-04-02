#!/usr/bin/perl -w
use strict;
use Prophet::Test::Arena;

Prophet::Test::Arena->run_from_yaml;

__DATA__
--- 
chickens: 
  - CLANE
  - COLMODE
  - USTIANSKY
recipe: 
  - 
    - CLANE
    - create_record
    - 
      props: 
        - --the_Power_of_the_Black_Land
        - clange
        - --the_Lord_of_Mordor
        - splatt
        - --Sauron_the_Deceiver
        - awkkkkkk
        - --the_Black_Hand
        - glurpp
        - --the_Lord_of_the_Rings
        - bloop
      result: 4
  - 
    - COLMODE
    - sync_from_peer
    - 
      from: CLANE
  - 
    - CLANE
    - update_record
    - 
      props: 
        Sauron_the_Deceiver: bloop
        the_Black_Hand: zapeth
        the_Lord_of_the_Rings: splatt
      record: 4
  - 
    - COLMODE
    - update_record
    - 
      props: 
        Sauron_the_Deceiver: splatt
        the_Black_Hand: clange
        the_Lord_of_Mordor: glurpp
        the_Lord_of_the_Rings: bloop
        the_Power_of_the_Black_Land: awkkkkkk
      record: 4
  - 
    - USTIANSKY
    - sync_from_peer
    - 
      from: COLMODE
  - 
    - COLMODE
    - sync_from_peer
    - 
      from: CLANE
  - 
    - CLANE
    - sync_from_peer
    - 
      from: USTIANSKY
  - 
    - CLANE
    - sync_from_peer
    - 
      from: COLMODE
