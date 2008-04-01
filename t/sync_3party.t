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
    - create_record
    - props:
        - --the_Enemy
        - zamm
        - --the_Eye_of_Barad_dur
        - pow
        - --Sauron
        - zam
        - --the_Power_of_the_Black_Land
        - owww
        - --the_Nameless
        - powie
      result: 3
  -
    - STLACY
    - create_record
    - props:
        - --the_Master
        - zwapp
        - --the_Dark_Power
        - ouch_eth
        - --the_Lord_of_the_Ring
        - clunk_eth
        - --the_Nameless
        - kayo
        - --Him
        - clash
      result: 4
  -
    - ZEV
    - create_record
    - props:
        - --the_Ring_Maker
        - clange
        - --the_Black_Hand
        - urkkk
        - --the_Black_Master
        - rakkk
        - --the_Eye_of_Barad_dur
        - crunch
        - --the_Dark_Lord
        - crr_aaack
      result: 5
  -
    - SKNPP
    - create_record
    - props:
        - --the_Great_Eye
        - pam
        - --the_Master
        - clunk
        - --the_Lord_of_the_Rings
        - thunk
        - --the_Evil_Eye
        - zlonk
        - --the_Lord_of_the_Earth
        - swoosh
      result: 6
  -
    - STLACY
    - create_record
    - props:
        - --Thauron
        - zapeth
        - --the_Enemy
        - rakkk
        - --Sauron_the_Deceiver
        - whamm
        - --the_Lord_of_Barad_dur
        - z_zwap
        - --the_Lord_of_the_Rings
        - zlopp
      result: 7
  -
    - ZEV
    - create_record
    - props:
        - --the_Lord_of_the_Earth
        - zok
        - --the_Black_Hand
        - boff
        - --the_Dark_Lord_of_Mordor
        - whamm
        - --the_Master
        - ker_sploosh
        - --the_Lord_of_the_Rings
        - zamm
      result: 8
  -
    - SKNPP
    - create_record
    - props:
        - --the_Enemy
        - pow
        - --the_Lord_of_Mordor
        - slosh
        - --the_Lord_of_the_Ring
        - boff
        - --the_Nameless_Eye
        - vronk
        - --Him
        - crash
      result: 9
  -
    - STLACY
    - create_record
    - props:
        - --the_Dark_Lord
        - zlott
        - --the_Eye_of_Barad_dur
        - rakkk
        - --the_Nameless_Eye
        - swoosh
        - --the_Lord_of_the_Ring
        - aiieee
        - --the_Red_Eye
        - bang_eth
      result: 10
  -
    - ZEV
    - update_record
    - props:
        the_Black_Hand: urkkk
        the_Black_Master: crr_aaack
        the_Dark_Lord: rakkk
        the_Eye_of_Barad_dur: clange
        the_Master: uggh
        the_Ring_Maker: crunch
      record: 5
  -
    - SKNPP
    - create_record
    - props:
        - --the_Lord_of_the_Dark_Tower
        - pow
        - --Gorthaur_the_Cruel
        - swa_a_p
        - --the_Great_Eye
        - rip
        - --the_Lord_of_Mordor
        - thwapp
        - --the_Black_One
        - swoosh
      result: 11
  -
    - STLACY
    - create_record
    - props:
        - --the_Lord_of_the_Earth
        - zam
        - --the_Lidless_Eye
        - zowie
        - --the_Nameless_Eye
        - awk
        - --Him
        - zlott
        - --the_Dark_Lord_of_Mordor
        - zap
      result: 12
  -
    - ZEV
    - update_record
    - props:
        the_Eye_of_Barad_dur: kayo
        the_Lidless_Eye: ouch_eth
        the_Lord_of_Mordor: zowie
        the_Master: touche
      record: 2
  -
    - SKNPP
    - update_record
    - props:
        Gorthaur_the_Cruel: thwapp
        the_Black_One: swoosh
        the_Great_Eye: swa_a_p
        the_Lord_of_Mordor: rip
      record: 11
  -
    - STLACY
    - create_record
    - props:
        - --the_Enemy
        - thwacke
        - --the_Ring_Maker
        - plop
        - --the_Eye_of_Barad_dur
        - boff
        - --the_Shadow
        - thwape
        - --the_Lord_of_the_Dark_Tower
        - swa_a_p
      result: 13
  -
    - ZEV
    - create_record
    - props:
        - --the_Nameless_One
        - boff
        - --the_Dark_Lord_of_Mordor
        - zgruppp
        - --the_Black_Hand
        - powie
        - --the_Lord_of_Barad_dur
        - zam
        - --the_Master
        - swish
      result: 14
  -
    - SKNPP
    - update_record
    - props:
        Him: pow
        the_Enemy: boff
        the_Evil_Eye: spla_a_t
        the_Lord_of_Mordor: vronk
        the_Nameless_Eye: crash
      record: 9
  -
    - SKNPP
    - sync_from_peer
    - from: ZEV
  -
    - SKNPP
    - sync_from_peer
    - from: STLACY
  -
    - STLACY
    - sync_from_peer
    - from: ZEV
  -
    - SKNPP
    - sync_from_peer
    - from: STLACY
