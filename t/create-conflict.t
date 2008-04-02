#!/usr/bin/perl -w
use strict;
use Prophet::Test::Arena;

Prophet::Test::Arena->run_from_yaml;

__DATA__
--- 
chickens: 
  - EIDOLON
  - KIRSLE
  - RZILAVEC
recipe: 
  - 
    - KIRSLE
    - create_record
    - 
      props: 
        - --the_Dark_Lord_of_Mordor
        - cr_r_a_a_ck
      result: 8
  - 
    - RZILAVEC
    - create_record
    - 
      props: 
        - --the_Dark_Lord_of_Mordor
        - kapow
      result: 9
  - 
    - EIDOLON
    - create_record
    - 
      props: 
        - --the_Shadow
        - eee_yow
      result: 10
  - 
    - RZILAVEC
    - sync_from_peer
    - 
      from: EIDOLON
  - 
    - RZILAVEC
    - create_record
    - 
      props: 
        - --the_Lord_of_the_Earth
        - zamm
      result: 11
  - 
    - KIRSLE
    - sync_from_peer
    - 
      from: RZILAVEC
  - 
    - EIDOLON
    - sync_from_peer
    - 
      from: KIRSLE
  - 
    - EIDOLON
    - sync_from_peer
    - 
      from: RZILAVEC
