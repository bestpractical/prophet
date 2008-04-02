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
    - EIDOLON
    - create_record
    - 
      props: 
        - --the_Nameless
        - ker_sploosh
        - --the_Black_Hand
        - awkkkkkk
        - --the_Evil_Eye
        - uggh
        - --the_Red_Eye
        - ouch
        - --the_Lord_of_the_Earth
        - blurp
      result: 1
  - 
    - KIRSLE
    - create_record
    - 
      props: 
        - --the_Black_Master
        - bam
        - --Gorthaur_the_Cruel
        - zamm
        - --the_Lidless_Eye
        - kapow
        - --the_Nameless_Eye
        - zlopp
        - --Him
        - clange
      result: 2
  - 
    - RZILAVEC
    - create_record
    - 
      props: 
        - --He
        - clank
        - --the_Ring_Maker
        - z_zwap
        - --the_Enemy
        - splatt
        - --the_Lord_of_the_Rings
        - thwapp
        - --the_Dark_Power
        - kayo
      result: 3
  - 
    - EIDOLON
    - create_record
    - 
      props: 
        - --the_Enemy
        - uggh
        - --the_Red_Eye
        - zwapp
        - --the_Shadow
        - whap
        - --Him
        - ooooff
        - --the_Lord_of_the_Ring
        - zlott
      result: 4
  - 
    - KIRSLE
    - create_record
    - 
      props: 
        - --the_Lord_of_the_Ring
        - zlonk
        - --the_Lord_of_the_Dark_Tower
        - awkkkkkk
        - --the_Lord_of_Barad_dur
        - thwacke
        - --the_Nameless
        - cr_r_a_a_ck
        - --the_Black_Master
        - whap
      result: 5
  - 
    - RZILAVEC
    - create_record
    - 
      props: 
        - --the_Lord_of_Mordor
        - awk
        - --the_Evil_Eye
        - zlott
        - --the_Lidless_Eye
        - wham_eth
        - --the_Red_Eye
        - zgruppp
        - --the_Black_One
        - flrbbbbb
      result: 6
  - 
    - EIDOLON
    - create_record
    - 
      props: 
        - --the_Black_Master
        - whack_eth
        - --the_Nameless
        - eee_yow
        - --the_Great_Eye
        - bam
        - --Thauron
        - sock
        - --the_Dark_Lord
        - touche
      result: 7
  - 
    - KIRSLE
    - create_record
    - 
      props: 
        - --the_Dark_Lord_of_Mordor
        - cr_r_a_a_ck
        - --the_Ring_Maker
        - vronk
        - --the_Eye_of_Barad_dur
        - powie
        - --the_Black_Hand
        - zok
        - --the_Lord_of_the_Earth
        - crash
      result: 8
  - 
    - RZILAVEC
    - create_record
    - 
      props: 
        - --the_Dark_Lord_of_Mordor
        - kapow
        - --the_Shadow
        - zowie
        - --the_Great_Eye
        - thunk
        - --Gorthaur_the_Cruel
        - thwape
        - --the_Dark_Power
        - swish
      result: 9
  - 
    - EIDOLON
    - create_record
    - 
      props: 
        - --the_Shadow
        - eee_yow
        - --Gorthaur_the_Cruel
        - pam
        - --the_Great_Eye
        - ooooff
        - --the_Power_of_the_Black_Land
        - thwacke
        - --the_Nameless
        - zapeth
      result: 10
  - 
    - RZILAVEC
    - sync_from_peer
    - 
      from: EIDOLON
  - 
    - EIDOLON
    - delete_record
    - 
      record: 4
  - 
    - KIRSLE
    - update_record
    - 
      props: 
        Gorthaur_the_Cruel: bam
        Him: zlopp
        the_Black_Master: zamm
        the_Lidless_Eye: kapow
        the_Nameless_Eye: clange
      record: 2
  - 
    - RZILAVEC
    - create_record
    - 
      props: 
        - --the_Lord_of_the_Earth
        - zamm
        - --the_Dark_Lord_of_Mordor
        - thwacke
        - --the_Lord_of_Mordor
        - zok
        - --the_Dark_Power
        - wham_eth
        - --the_Lord_of_the_Ring
        - z_zwap
      result: 11
  - 
    - EIDOLON
    - update_record
    - 
      props: 
        the_Black_Hand: uggh
        the_Evil_Eye: blurp
        the_Lord_of_Barad_dur: klonk
        the_Lord_of_the_Earth: awkkkkkk
        the_Red_Eye: ker_sploosh
      record: 1
  - 
    - RZILAVEC
    - sync_from_peer
    - 
      from: KIRSLE
  - 
    - EIDOLON
    - update_record
    - 
      props: 
        the_Black_Master: sock
        the_Dark_Lord: bam
        the_Dark_Power: bloop
        the_Great_Eye: eee_yow
        the_Nameless: touche
      record: 7
  - 
    - KIRSLE
    - sync_from_peer
    - 
      from: RZILAVEC
  - 
    - RZILAVEC
    - update_record
    - 
      props: 
        Him: uggh
        the_Enemy: zlott
        the_Lord_of_the_Ring: whap
        the_Shadow: ooooff
      record: 4
  - 
    - EIDOLON
    - sync_from_peer
    - 
      from: KIRSLE
  - 
    - KIRSLE
    - update_record
    - 
      props: 
        the_Black_Hand: ker_sploosh
        the_Evil_Eye: blurp
        the_Lord_of_the_Earth: ouch
        the_Nameless: awkkkkkk
      record: 1
  - 
    - RZILAVEC
    - create_record
    - 
      props: 
        - --the_Black_Hand
        - biff
        - --the_Lord_of_the_Rings
        - powie
        - --Sauron
        - crunch_eth
        - --the_Ring_Maker
        - crr_aaack
        - --the_Black_One
        - pow
      result: 12
  - 
    - KIRSLE
    - sync_from_peer
    - 
      from: RZILAVEC
  - 
    - KIRSLE
    - sync_from_peer
    - 
      from: EIDOLON
  - 
    - EIDOLON
    - sync_from_peer
    - 
      from: RZILAVEC
  - 
    - RZILAVEC
    - sync_from_peer
    - 
      from: KIRSLE
  - 
    - RZILAVEC
    - sync_from_peer
    - 
      from: EIDOLON
  - 
    - KIRSLE
    - sync_from_peer
    - 
      from: EIDOLON
  - 
    - KIRSLE
    - sync_from_peer
    - 
      from: EIDOLON
  - 
    - KIRSLE
    - sync_from_peer
    - 
      from: RZILAVEC
  - 
    - EIDOLON
    - sync_from_peer
    - 
      from: RZILAVEC
