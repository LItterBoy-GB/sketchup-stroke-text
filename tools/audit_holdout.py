"""Independently verify held-out LFF segments against source glyph ink."""
import argparse, json, math
from pathlib import Path
import numpy as np
from PIL import ImageFont
from generate_sample import render, ink_safe

root=Path(__file__).resolve().parent
p=argparse.ArgumentParser();p.add_argument('--font',required=True);args=p.parse_args()
font=ImageFont.truetype(args.font,256)
data=(root/'fonts/hei-improved-holdout.lff').read_text(encoding='utf8').splitlines()
glyphs={}; code=None
for line in data:
    if line.startswith('['): code=int(line[1:line.index(']')],16);glyphs[code]=[]
    elif line and not line.startswith('#'):
        glyphs[code].append([[float(v) for v in pair.split(',')] for pair in line.split(';')])
fail=[]; segs=0
for code,paths in glyphs.items():
    ink,x0,y0=render(font,chr(code))
    for path in paths:
        poly=np.array([[x*33.28+x0,y0-y*33.28] for x,y in path]);segs+=len(poly)-1
        if not ink_safe(poly,ink): fail.append('U+%04X'%code)
result={'glyphs':len(glyphs),'segments':segs,'paths_with_samples_outside_thresholded_ink':len(fail),'failed_glyphs':sorted(set(fail)),'definition':'Checks samples every 0.5 raster pixel, not a continuous or typographic correctness proof.'}
(root/'audit-holdout.json').write_text(json.dumps(result,indent=2),encoding='utf8')
print(json.dumps(result))
