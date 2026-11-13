"""Add both space advances to a generated full font; create summary."""
import argparse, hashlib, json, re
from pathlib import Path
from PIL import ImageFont
from font_cmap import supported

root=Path(__file__).resolve().parent
p=argparse.ArgumentParser();p.add_argument('--font',required=True);a=p.parse_args()
font=ImageFont.truetype(a.font,256); source=(root/'fonts/hei-improved-full.lff').read_text(encoding='utf8')
codes={int(x,16) for x in re.findall(r'^\[([0-9A-Fa-f]+)\]',source,re.M)}
cmap=supported(a.font)
for code in (0x20,0x3000):
    if code not in cmap: raise ValueError('source cmap has no U+%04X'%code)
    if code in codes: raise ValueError('unexpected duplicate space glyph')
    source+='\n[%04X]\n# Advance: %.8f\n'%(code,font.getlength(chr(code))*10/(256*1.3))
dest=root/'fonts/hei-improved.lff';dest.write_text(source,encoding='utf8',newline='\n')
data=json.loads((root/'data-full.json').read_text(encoding='utf8'))
orig=set((root/'charset.txt').read_text(encoding='utf8')); final={chr(c) for c in codes}|{' ','\u3000'}
def gb(a,b):
    chars=set()
    for x in range(a,b+1):
        for y in range(0xa1,0xff):
            try: chars.add(bytes([x,y]).decode('gb2312'))
            except UnicodeDecodeError: pass
    return chars
g1,g2=gb(0xb0,0xd7),gb(0xd8,0xf7)
summary={'font_sha256':hashlib.sha256(dest.read_bytes()).hexdigest(),'glyph_records':len(final),'nonempty_glyphs':len(codes),'spaces':['U+0020','U+3000'],'space_advances':{f'U+{c:04X}':font.getlength(chr(c))*10/(256*1.3) for c in (0x20,0x3000)},'missing_requested':sorted('U+%04X'%ord(c) for c in orig-final),'gb2312_level1_nonempty':len({ord(c) for c in g1}&codes),'gb2312_level2_nonempty':len({ord(c) for c in g2}&codes),'generated_segments':sum(v['segments'] for v in data['characters'].values()),'cycle_tails_removed':sum(len(v['removed_cycle_tails']) for v in data['characters'].values()),'dot_fallbacks':sum(v.get('dot_fallback_count',0) for v in data['characters'].values())}
(root/'full-summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps(summary,ensure_ascii=False))
