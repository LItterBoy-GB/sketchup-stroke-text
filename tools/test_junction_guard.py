# SPDX-License-Identifier: AGPL-3.0-or-later
"""Regression for split crossing protection; requires the pinned Noto source."""
import argparse, math, re
from pathlib import Path
from PIL import ImageFont
from generate_sample import render, graph, im, prune_cycle_tails, extract

p=argparse.ArgumentParser();p.add_argument('--font',required=True);p.add_argument('--lff',required=True);a=p.parse_args()
font=ImageFont.truetype(a.font,256)
ink,x,y=render(font,chr(0x7533)); original,adj=graph(im.thin(ink))
kept,removed=prune_cycle_tails(original,adj,ink)
assert any(len(adj[q])>=3 and q!=(51,134) and math.dist(q,(51,134))<=2 for q in adj), 'missing split junction'
assert not any(v['junction_yx']==[51,134] for v in removed), 'crossing branch pruned'
assert any((51,134) in path and len(path)>=30 for path in kept), 'expected branch absent'

text=Path(a.lff).read_text(encoding='utf8')
def ends(code):
    m=re.search(r'(?ms)^\[%04X\]\n(.*?)(?=^\[|\Z)'%code,text)
    assert m, 'missing glyph U+%04X'%code
    edges=set()
    for line in m.group(1).splitlines():
        if not line or line.startswith('#'): continue
        pts=[tuple(map(float,p.split(','))) for p in line.split(';')]
        edges.update(tuple(sorted((a,b))) for a,b in zip(pts,pts[1:]) if a!=b)
    degrees={}
    for a,b in edges:
        degrees[a]=degrees.get(a,0)+1;degrees[b]=degrees.get(b,0)+1
    return sum(n==1 for n in degrees.values())
for code,count in [(0x7533,2),(0x7532,1),(0x7531,1),(0x4e32,2),(0x4e2d,2),(0x53e3,0)]:
    assert ends(code)==count, 'unexpected endpoints U+%04X'%code
print('PASS: split crossing branch protected; sample endpoint topology')
