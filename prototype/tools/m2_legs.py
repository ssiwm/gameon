"""Dopisuje do szkicu (z m2_ladder.py) listę odcinków dla m2_route.gd. python m2_legs.py <z1_m2_ladder_*.json>
Odcinek z "expect_fail" ma NIE mieć drogi; "closed" to przegrody uznane za całe (domyślnie wszystkie: | q % +), "solid" dodatkowe bryły [c0, r0, c1, r1]."""
import sys, json
p = sys.argv[1]; d = json.load(open(p)); parts = d["meta"]["parts"]
S=[5,25]; G1=[94,25]; G2=[180,39]; G3=[236,21]; G4=[264,17]; D=[266,50]; E=[14,50]
MAST = [[262,26,282,43]]                  # szyb masztu (jedyne dzisiejsze zejście do tunelu)
L = [
 {"name":"S -> G1 powierzchnią","a":S,"b":G1},
 {"name":"G1 -> G2 bagnem","a":G1,"b":G2},
 {"name":"G2 -> G3","a":G2,"b":G3},
 {"name":"G3 -> G4","a":G3,"b":G4},
 {"name":"G4 -> drezyna","a":G4,"b":D},
 {"name":"drezyna -> E (tor)","a":D,"b":E},
]
if "C" not in parts:
    L += [{"name":"bez zejścia C: hala -> tor tylko szybem masztu","a":G2,"b":[206,50],"closed":"|q%"}]
if "C" in parts:
    L += [
     {"name":"C: magazyn -> tor (kratka cała, od środka)","a":[218,39],"b":[206,50]},
     {"name":"C: tor -> magazyn","a":[206,50],"b":[218,39]},
     {"name":"C: G2 -> tor przy zejściu (kratka rozbita)","a":G2,"b":[206,50],"closed":"|q%"},
     {"name":"C: G2 -> G4 tunelem (kratka rozbita, bez pompowni)","a":G2,"b":G4,"closed":"|q%","solid":[[222,0,250,25]]},
     {"name":"C: G3 -> drezyna przez halę i zejście (kratka rozbita)","a":G3,"b":D,"closed":"|q%","solid":[[270,26,279,43]]},
     {"name":"C: kratka cała: hala -> tor tylko szybem masztu","a":G2,"b":[206,50]},
    ]
if "A" in parts:
    col = d["meta"]["collapse"]
    L += [
     {"name":"A: S -> G1 przepustem (dziedziniec zamknięty)","a":S,"b":G1,"solid":[[43,10,58,25]]},
     {"name":"A: właz przepustu -> właz studni","a":[40,25],"b":[62,25],"solid":[[43,10,58,25]]},
     {"name":"A: deski całe: studnia nie prowadzi do toru","a":[62,25],"b":[66,50],"solid":MAST,"expect_fail":True},
     {"name":"A: studnia -> tor (deski rozbite)","a":[62,25],"b":[66,50],"closed":"|q+"},
     {"name":"A: tor -> studnia (deski rozbite)","a":[66,50],"b":[62,25],"closed":"|q+"},
     {"name":"A: S -> drezyna w kol. 56 (odrodzenie w ewakuacji, przed zawałem)","a":S,"b":[56,50],"closed":"|q+"},
     {"name":"A przed zawałem: G4 -> E pieszo przez studnię","a":G4,"b":E,"closed":"|q+","solid":MAST},
     # zawał podestu przy nadawaniu — po nim do E tylko torem
     {"name":"A po zawale: G4 -> E pieszo bez szybu masztu","a":G4,"b":E,"closed":"|q+","solid":col+MAST,"expect_fail":True},
     {"name":"A po zawale: S -> E pieszo bez szybu masztu","a":S,"b":E,"closed":"|q+","solid":col+MAST,"expect_fail":True},
     {"name":"A po zawale: S -> G4 nadal (przepust, studnia)","a":S,"b":G4,"closed":"|q+","solid":col},
     {"name":"A po zawale: G4 -> drezyna","a":G4,"b":D,"solid":col},
     {"name":"A po zawale: drezyna -> E (tor)","a":D,"b":E,"solid":col},
    ]
if "A" in parts and "C" in parts:
    L += [{"name":"A+C: G1 -> G2 tunelem (deski i kratka rozbite, bez bagna)","a":G1,"b":G2,"closed":"|q","solid":[[101,0,150,25]]}]
if "B" in parts:
    L += [
     {"name":"B: skrytka -> tor","a":[147,39],"b":[136,50]},
     {"name":"B: tor -> skrytka","a":[136,50],"b":[147,39]},
     {"name":"B: G2 -> tor przy zsypie (mur rozbity)","a":G2,"b":[136,50],"closed":"|%+"},
    ]
if "A" in parts and "B" in parts:
    L += [{"name":"A+B: G1 -> G2 tunelem (deski i mur rozbite, bez bagna)","a":G1,"b":G2,"closed":"|+","solid":[[101,0,150,25]]}]
d["legs"] = L
json.dump(d, open(p, 'w'))
