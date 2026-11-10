"""Zrzut siatki mapy z pliku .gd do json + lista znaczników. Użycie: python m2_dump.py <z1_m2.gd> <out.json>"""
import sys, re, json, collections
src = open(sys.argv[1], encoding='utf-8').read()
body = src[src.index('const MAP := ['):]
rows = re.findall(r'^\t"([^"]*)",?$', body, re.M)
W = len(rows[0]); assert all(len(r) == W for r in rows), [len(r) for r in rows]
json.dump({"rows": rows}, open(sys.argv[2], 'w'))
print(W, 'x', len(rows))
marks = collections.defaultdict(list)
for r, row in enumerate(rows):
    for c, ch in enumerate(row):
        if ch not in '#.bwC=-m~O':
            marks[ch].append((c, r))
for ch in sorted(marks):
    print(ch, len(marks[ch]), sorted(marks[ch]))
# segmenty kładek i brył w wierszach
for r, row in enumerate(rows):
    segs = [(m.start(), m.end()-1, m.group()[0]) for m in re.finditer(r'=+|-+|m+|~+|O+', row)]
    if segs: print('r', r, segs)
