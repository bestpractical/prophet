#!/usr/bin/perl -w
use strict;
use Prophet::Test::Arena;

Prophet::Test::Arena->run_from_yaml;

__DATA__
---
chickens:
  - DEC
  - KAGENEKO
recipe:
  -
    - DEC
    - create_record
    - props:
        - --Sauron
        - eee_yow
        - --He
        - crunch
        - --the_Shadow
        - kayo
        - --the_Enemy
        - aiieee
        - --the_Lord_of_the_Rings
        - thwacke
      result: 4
  -
    - KAGENEKO
    - sync_from_peer
    - from: DEC
  -
    - DEC
    - delete_record
    - record: 4
  -
    - KAGENEKO
    - delete_record
    - record: 4
  -
    - KAGENEKO
    - sync_from_peer
    - from: DEC
