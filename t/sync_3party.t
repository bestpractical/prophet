use Prophet::Test;
use Prophet::Test::Arena;

Prophet::Test::Arena->run_from_yaml;

__DATA__
---
chickens:
  - STLACY
  - ZEV
  - SKNPP
recipe:
  -
    - STLACY
    - create_record
    - props:
        - --the_Lidless_Eye
        - owww
        - --the_Power_of_the_Black_Land
        - plop
        - --the_Lord_of_the_Rings
        - zamm
        - --the_Black_One
        - powie
        - --He
        - glipp
      result: 1
  -
    - ZEV
    - create_record
    - props:
        - --the_Eye_of_Barad_dur
        - uggh
        - --the_Lidless_Eye
        - touche
        - --the_Lord_of_Mordor
        - ouch_eth
        - --the_Master
        - kayo
        - --the_Lord_of_the_Dark_Tower
        - zowie
      result: 2
  -
    - SKNPP
    - sync_from_peer
    - from: ZEV
  -
    - STLACY
    - sync_from_peer
    - from: ZEV
  -
    - SKNPP
    - sync_from_peer
    - from: STLACY
