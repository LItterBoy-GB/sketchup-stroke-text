"""Read Unicode cmap format 4/12 from sfnt; reject missing/.notdef (gid 0)."""
import struct
from pathlib import Path

def supported(path):
    b=Path(path).read_bytes()
    u16=lambda p:struct.unpack_from('>H',b,p)[0]
    u32=lambda p:struct.unpack_from('>I',b,p)[0]
    tables=u16(4); cmap=None
    for i in range(tables):
        p=12+i*16
        if b[p:p+4]==b'cmap': cmap=u32(p+8); break
    if cmap is None: raise ValueError('font has no cmap')
    codes=set()
    for i in range(u16(cmap+2)):
        p=cmap+4+8*i; platform=u16(p); encoding=u16(p+2)
        if not (platform==0 or platform==3 and encoding in (1,10)): continue
        sub=cmap+u32(p+4); fmt=u16(sub)
        if fmt==12:
            for j in range(u32(sub+12)):
                pos=sub+16+12*j; start,end,gid=struct.unpack_from('>III',b,pos)
                codes.update(range(start+(gid==0),end+1))
        elif fmt==4:
            count=u16(sub+6)//2; end_base=sub+14; start_base=end_base+count*2+2; delta_base=start_base+count*2; range_base=delta_base+count*2
            for j in range(count):
                start=u16(start_base+j*2); end=u16(end_base+j*2); delta=u16(delta_base+j*2); ro=u16(range_base+j*2)
                for ch in range(start,min(end,0xfffe)+1):
                    if ro==0: gid=(ch+delta)&0xffff
                    else:
                        off=range_base+j*2+ro+2*(ch-start)
                        gid=u16(off); gid=((gid+delta)&0xffff) if gid else 0
                    if gid: codes.add(ch)
    return codes
