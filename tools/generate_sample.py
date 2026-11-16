"""Research prototype. Extract a connectivity-preserving skeleton graph.

Uses penplot's AGPL-3.0-or-later image.py / geometry.py (see vendor and LICENSE).
Input font is separately licensed under SIL OFL 1.1. No per-glyph bbox scaling.
"""
import argparse, hashlib, json, math, time
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from vendor import image as im
from font_cmap import supported

ROOT = Path(__file__).resolve().parent
SAMPLE = '一二三十口日田中水永结构图厅卫电门墙建筑装修给排水消防喷淋警馨赢戴藏疆鑫矗囊点小心六八标高尺寸轴线国'

def render(font, char):
    box = font.getbbox(char, anchor='ls')
    pad = 8
    x0, y0 = pad-box[0], pad-box[1]
    canvas = Image.new('L', (box[2]-box[0]+2*pad, box[3]-box[1]+2*pad), 0)
    ImageDraw.Draw(canvas).text((x0,y0), char, font=font, fill=255, anchor='ls')
    return np.asarray(canvas,dtype=np.float32)/255, x0, y0

def graph(skel):
    # Delete diagonal adjacency if either orthogonal detour is present.
    pts = set(map(tuple, np.argwhere(skel)))
    adj = {}
    for y,x in pts:
        links=[]
        for dy in (-1,0,1):
            for dx in (-1,0,1):
                if not (dy or dx) or (y+dy,x+dx) not in pts: continue
                if dy and dx and ((y+dy,x) in pts or (y,x+dx) in pts): continue
                links.append((y+dy,x+dx))
        adj[(y,x)] = sorted(links)
    used=set(); paths=[]
    def edge(a,b): return tuple(sorted((a,b)))
    def walk(a,b):
        path=[a,b]; used.add(edge(a,b)); prev,cur=a,b
        while len(adj[cur]) == 2:
            nxt=next(v for v in adj[cur] if v != prev)
            if edge(cur,nxt) in used: break
            path.append(nxt); used.add(edge(cur,nxt)); prev,cur=cur,nxt
        return path
    for node in sorted(adj):
        if len(adj[node]) == 0:
            # Preserve isolated dot pixel as one short segment, not deletion.
            y,x=node; paths.append([(y,x),(y,x+0.5)])
        elif len(adj[node]) != 2:
            for n in adj[node]:
                if edge(node,n) not in used: paths.append(walk(node,n))
    for node in sorted(adj):
        for n in adj[node]:
            if edge(node,n) not in used: paths.append(walk(node,n))
    return paths, adj

def ink_safe(poly, ink):
    for a,b in zip(poly,poly[1:]):
        n=max(1,int(math.ceil(np.linalg.norm(b-a)*2)))
        for i in range(n+1):
            x,y=a+(b-a)*(i/n); x=int(round(x)); y=int(round(y))
            if y<0 or x<0 or y>=ink.shape[0] or x>=ink.shape[1] or ink[y,x]<0.5: return False
    return True

def missing_components(ink,skel):
    # Label exact 8-connected ink runs, and detect vanished skeleton blobs.
    mask=ink>=0.5; z=np.zeros((mask.shape[0],1),dtype=np.int8)
    d=np.diff(np.concatenate((z,mask.astype(np.int8),z),axis=1),axis=1)
    sy,sx=np.nonzero(d==1); ex=np.nonzero(d==-1)[1]-1
    runs=list(zip(sy.tolist(),sx.tolist(),ex.tolist())); parent=list(range(len(runs)))
    def find(i):
        while parent[i]!=i:
            parent[i]=parent[parent[i]]; i=parent[i]
        return i
    prevlo=prevhi=curlo=0; current=None
    for k,(y,x0,x1) in enumerate(runs):
        if y!=current:
            if current is not None and y==current+1: prevlo,prevhi=curlo,k
            else: prevlo=prevhi=k
            curlo,current=k,y; j=prevlo
        while j<prevhi and runs[j][2]<x0-1: j+=1
        jj=j
        while jj<prevhi and runs[jj][1]<=x1+1:
            ra,rb=find(jj),find(k)
            if ra!=rb: parent[rb]=ra
            jj+=1
    components={}
    for k,(y,x0,x1) in enumerate(runs): components.setdefault(find(k),[]).append((y,x0,x1))
    missing=[]
    for lines in components.values():
        if any(skel[y,x0:x1+1].any() for y,x0,x1 in lines): continue
        # A central actual ink pixel avoids off-mask bbox centroid fallback.
        y,x0,x1=max(lines,key=lambda r:r[2]-r[1]); x=(x0+x1)//2
        missing.append(np.array([[x,y],[x+0.5,y]],dtype=float))
    return missing

def prune_cycle_tails(paths, adj, ink):
    # Only a leaf attached to a degree-3 node on a loop, whose direction
    # continues a loop arm, is eligible. Isolated dots and off-loop ends stay.
    removed=[]; kept=[]
    for p in paths:
        if len(p)<2:
            kept.append(p); continue
        first, last=p[0],p[-1]
        if len(adj.get(first,()))==3 and len(adj.get(last,()))==1: seq=p
        elif len(adj.get(last,()))==3 and len(adj.get(first,()))==1: seq=list(reversed(p))
        else:
            kept.append(p); continue
        node=seq[0]; other=[x for x in adj[node] if x != seq[1]]
        # Node lies on a cycle iff its two other neighbours remain connected
        # after removing this node. Restrict to the source skeleton graph.
        seen={node}; stack=[other[0]]
        while stack and other[1] not in seen:
            v=stack.pop()
            if v in seen: continue
            seen.add(v); stack.extend(u for u in adj[v] if u not in seen)
        if other[1] not in seen:
            kept.append(p); continue
        y,x=node; distances=[]
        for yy in range(max(0,y-40),min(ink.shape[0],y+41)):
            for xx in range(max(0,x-40),min(ink.shape[1],x+41)):
                if ink[yy,xx]<0.5: distances.append(math.hypot(yy-y,xx-x))
        if not distances:
            kept.append(p); continue
        width=2*min(distances)
        length=sum(math.dist(a,b) for a,b in zip(seq,seq[1:]))
        # Adjacent junctions can be one split crossing; a short leaf on one
        # half may be a genuine stroke, not a frame corner overshoot.
        if any(q != node and len(links) >= 3 and math.dist(node,q) <= width
               for q,links in adj.items()):
            kept.append(p); continue
        # Compare arms at several pixels, rather than a potentially diagonal
        # one-pixel junction. All candidates remain inside the source ink.
        v=np.array(seq[min(5,len(seq)-1)],dtype=float)-np.array(node,dtype=float)
        opposite=False
        for arm in paths:
            if arm[0]==node: q=arm
            elif arm[-1]==node: q=list(reversed(arm))
            else: continue
            if q[1]==seq[1]: continue
            w=np.array(q[min(5,len(q)-1)],dtype=float)-np.array(node,dtype=float)
            if np.linalg.norm(v) and np.linalg.norm(w) and np.dot(v,w)/(np.linalg.norm(v)*np.linalg.norm(w)) < -0.9:
                opposite=True
        if length <= 1.25*width and opposite:
            removed.append({'length_px':length,'local_width_px':width,'junction_yx':[int(y),int(x)]})
        else: kept.append(p)
    return kept,removed

def extract(font,char,tol,prune):
    ink,x0,y0=render(font,char)
    skel=im.thin(ink)
    paths,adj=graph(skel)
    paths,removed=prune_cycle_tails(paths,adj,ink) if prune else (paths,[])
    result=[]
    for p in paths:
        xy=np.array([[x,y] for y,x in p],dtype=float)
        for eps in (tol,tol/2,0):
            reduced=im.rdp_xy(xy,eps) if eps else xy
            if ink_safe(reduced,ink) or not eps: break
        result.append(reduced)
    fallback=missing_components(ink,skel)
    result.extend(fallback)
    return result,ink,x0,y0,adj,removed,len(fallback)

def main():
    parser=argparse.ArgumentParser(); parser.add_argument('--font',required=True); parser.add_argument('--size',type=int,default=256); parser.add_argument('--tolerance',type=float,default=1.2); parser.add_argument('--prune-cycle-tails',action='store_true'); parser.add_argument('--tag',default='sample'); parser.add_argument('--charset-file'); parser.add_argument('--no-preview',action='store_true'); parser.add_argument('--checkpoint'); parser.add_argument('--skip-unsupported',action='store_true'); args=parser.parse_args()
    font=ImageFont.truetype(args.font,args.size)
    em=args.size*1.3
    out=['# Format: LibreCAD Font 1','# LetterSpacing: 0','# WordSpacing: %.8f'%(font.getlength(' ')*10/em),'# LineSpacingFactor: 1.3','# Topology-preserving skeleton; modified Noto font; SIL OFL 1.1']
    info={}; chars=''.join(dict.fromkeys(Path(args.charset_file).read_text(encoding='utf8') if args.charset_file else SAMPLE)); images=[]
    cmap=supported(args.font); unsupported=[ch for ch in chars if ord(ch) not in cmap]
    if unsupported:
        # 上下标等合成码位不在源字体 cmap 中，由 make_superscript/make_subscript 生成
        if not args.skip_unsupported: raise ValueError('source cmap missing: '+repr(unsupported))
        print('skipping %d codepoint(s) absent from source cmap: %s'
              %(len(unsupported),' '.join('U+%04X'%ord(c) for c in unsupported)),flush=True)
        chars=''.join(ch for ch in chars if ord(ch) in cmap)
    if args.checkpoint and not args.no_preview: raise ValueError('checkpoint requires --no-preview')
    start=time.monotonic(); source_sha=hashlib.sha256(Path(args.font).read_bytes()).hexdigest()
    signature={'font_sha':source_sha,'chars_sha':hashlib.sha256(chars.encode('utf8')).hexdigest(),'generator_sha':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'size':args.size,'tolerance':args.tolerance,'prune':args.prune_cycle_tails}
    checkpoint=Path(args.checkpoint) if args.checkpoint else None; resume=0
    if checkpoint and checkpoint.exists():
        state=json.loads(checkpoint.read_text(encoding='utf8'))
        if state['signature']!=signature: raise ValueError('checkpoint does not match inputs or generator')
        resume=state['next_index']; out=state['out']; info=state['info']; print('resuming at %d/%d'%(resume,len(chars)),flush=True)
    for idx,ch in enumerate(chars):
        if idx<resume: continue
        if idx and idx%500==0:
            if checkpoint:
                temporary=checkpoint.with_suffix('.tmp')
                temporary.write_text(json.dumps({'signature':signature,'next_index':idx,'out':out,'info':info},ensure_ascii=False),encoding='utf8')
                temporary.replace(checkpoint)
            print('progress %d/%d elapsed %.1fs current U+%04X'%(idx,len(chars),time.monotonic()-start,ord(ch)),flush=True)
        if ch.isspace():
            info[ch]={'blank_space':True,'paths':0,'segments':0,'removed_cycle_tails':[]}; continue
        paths,ink,x0,y0,adj,removed,fallback_count=extract(font,ch,args.tolerance,args.prune_cycle_tails)
        if not paths: raise ValueError('non-space glyph has no strokes: U+%04X'%ord(ch))
        out += ['[%04X]'%ord(ch), '# Advance: %.8f'%(font.getlength(ch)*10/em)]
        for path in paths:
            out.append(';'.join('%.6f,%.6f'%((x-x0)*10/em,(y0-y)*10/em) for x,y in path))
        out.append('')
        nodes=len(adj); edges=sum(map(len,adj.values()))//2
        info[ch]={'paths':len(paths),'segments':sum(len(p)-1 for p in paths),'source_graph_nodes':nodes,'source_graph_edges':edges,'source_junction_nodes':sum(len(v)>2 for v in adj.values()),'removed_cycle_tails':removed,'dot_fallback_count':fallback_count}
        if not args.no_preview:
            canvas=Image.new('RGB',(160,160),'white'); d=ImageDraw.Draw(canvas)
            factor=min(135/ink.shape[1],135/ink.shape[0]); offx=(160-ink.shape[1]*factor)/2; offy=(160-ink.shape[0]*factor)/2
            for p in paths:
                d.line([(offx+x*factor,offy+y*factor) for x,y in p],fill='black',width=1)
            images.append((ch,canvas))
    (ROOT/('fonts/hei-improved-'+args.tag+'.lff')).write_text('\n'.join(out),encoding='utf8',newline='\n')
    if images:
        sheet=Image.new('RGB',(160*8,180*math.ceil(len(images)/8)),'white'); draw=ImageDraw.Draw(sheet)
        for i,(ch,pic) in enumerate(images):
            x=(i%8)*160;y=(i//8)*180;sheet.paste(pic,(x,y));draw.text((x+5,y+160), 'U+%04X'%ord(ch), fill='black')
        sheet.save(ROOT/('strokes-'+args.tag+'.png'))
    payload={'source_font_sha256':source_sha,'resolution':args.size,'rdp_tolerance_px':args.tolerance,'font_em_px':em,'prune_cycle_tails':args.prune_cycle_tails,'characters':info}
    (ROOT/('data-'+args.tag+'.json')).write_text(json.dumps(payload,ensure_ascii=False,indent=2),encoding='utf8')
    print('glyphs',len(chars),'segments',sum(v['segments'] for v in info.values()),'elapsed %.1fs'%(time.monotonic()-start))
if __name__ == '__main__': main()
