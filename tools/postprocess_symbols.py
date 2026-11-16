"""Two independent symbol post-passes for a generated LFF font.

--dots   Replace isolated dot strokes (two-point paths shorter than 0.05 units
         whose endpoints no other path shares) with a 0.3-unit segment along the
         original direction. SketchUp drops edges shorter than 0.001 inch, so at
         3.5 mm text height a 0.015-unit dot is invisible (0.005 mm); 0.3 units
         is 0.105 mm at the same height. Only symbol blocks are touched, and only
         genuinely dangling dots, so arrow tips and shared junction stubs stay.

--hollow Draw solid shapes with the matching outline glyph from the same font.
         A single-line font cannot fill a shape, so a solid triangle/circle
         skeletonizes to a short blob or a Y. Codepoint and advance are kept;
         only the geometry is replaced.

Run after finalize_font.py, before make_superscript.py / make_subscript.py.
"""
import argparse, math, re
from pathlib import Path

DOT_MAX = 0.05
DOT_TARGET = 0.3

SYMBOL_RANGES = [
    (0x0020, 0x007E), (0x00A0, 0x00BF), (0x00D7, 0x00D7), (0x00F7, 0x00F7),
    (0x2000, 0x206F), (0x2070, 0x209F), (0x20A0, 0x20CF), (0x2100, 0x214F),
    (0x2150, 0x218F), (0x2190, 0x21FF), (0x2200, 0x22FF), (0x2300, 0x23FF),
    (0x2460, 0x24FF), (0x2500, 0x25FF), (0x2600, 0x26FF), (0x3000, 0x303F),
    (0xFF00, 0xFFEF),
]

# solid -> outline, both present in the source font
HOLLOW_MAP = {0x25A0: 0x25A1, 0x25CF: 0x25CB, 0x25C6: 0x25C7,
              0x25B2: 0x25B3, 0x25BC: 0x25BD}


def split_blocks(text):
    header, blocks, cur, seen = [], [], None, False
    for line in text.split('\n'):
        m = re.match(r'^\[#?([0-9a-fA-F]{1,6})\]$', line.strip())
        if m:
            seen = True
            if cur is not None:
                blocks.append(cur)
            cur = [int(m.group(1), 16), [line]]
            continue
        if not seen:
            header.append(line)
        elif cur is not None:
            cur[1].append(line)
    if cur is not None:
        blocks.append(cur)
    return header, blocks


def is_geom(line):
    s = line.strip()
    return bool(s) and not s.startswith('#') and not re.match(r'^\[', s)


def parse(line):
    out = []
    for part in line.strip().split(';'):
        v = part.split(',')
        out.append((float(v[0]), float(v[1]), v[2] if len(v) > 2 else ''))
    return out


def fmt(x, y, bulge):
    s = '%.6f,%.6f' % (x, y)
    return s + ',' + bulge if bulge else s


def key(p):
    return (round(p[0], 4), round(p[1], 4))


def fix_dots(blocks):
    fixed = {}
    for cp, body in blocks:
        if not any(lo <= cp <= hi for lo, hi in SYMBOL_RANGES):
            continue
        idx = [i for i, line in enumerate(body) if is_geom(line)]
        if not idx:
            continue
        parsed = {i: parse(body[i]) for i in idx}
        usage = {}
        for pts in parsed.values():
            for p in pts:
                usage[key(p)] = usage.get(key(p), 0) + 1
        n = 0
        for i, pts in parsed.items():
            if len(pts) != 2:
                continue
            (x1, y1, b1), (x2, y2, b2) = pts
            length = math.hypot(x2 - x1, y2 - y1)
            if length >= DOT_MAX:
                continue
            if usage.get(key(pts[0]), 0) != 1 or usage.get(key(pts[1]), 0) != 1:
                continue
            ux, uy = ((x2 - x1) / length, (y2 - y1) / length) if length > 1e-9 else (1.0, 0.0)
            cx, cy = (x1 + x2) / 2.0, (y1 + y2) / 2.0
            half = DOT_TARGET / 2.0
            body[i] = fmt(cx - ux * half, cy - uy * half, b1) + ';' + \
                      fmt(cx + ux * half, cy + uy * half, b2)
            n += 1
        if n:
            fixed[cp] = n
    return fixed


def make_hollow(blocks):
    """Rewrite solid glyph bodies in place; returns the changed codepoints."""
    by_cp = {cp: body for cp, body in blocks}
    changed = []
    for solid, hollow in HOLLOW_MAP.items():
        if solid not in by_cp or hollow not in by_cp:
            continue
        geo = [line for line in by_cp[hollow] if is_geom(line)]
        if not geo:
            continue
        head = [line for line in by_cp[solid] if not is_geom(line)]
        while head and not head[-1].strip():
            head.pop()
        by_cp[solid][:] = head + geo
        changed.append((solid, hollow, len(geo)))
    return changed


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--lff', required=True)
    p.add_argument('--out')
    p.add_argument('--no-dots', action='store_true')
    p.add_argument('--no-hollow', action='store_true')
    a = p.parse_args()
    src, dst = Path(a.lff), Path(a.out or a.lff)

    header, blocks = split_blocks(src.read_text(encoding='utf8'))
    hollow = [] if a.no_hollow else make_hollow(blocks)
    fixed = {} if a.no_dots else fix_dots(blocks)

    chunks = ['\n'.join(body).rstrip('\n') for _, body in blocks]
    text = '\n'.join(header).rstrip('\n') + '\n' + '\n\n'.join(chunks) + '\n'
    dst.write_text(text, encoding='utf8', newline='\n')

    if hollow:
        print('hollow:', ' '.join('U+%04X<-U+%04X(%d)' % c for c in hollow))
    print('dots lengthened: %d glyph(s), %d segment(s)' % (len(fixed), sum(fixed.values())))
    for cp in sorted(fixed):
        print('  U+%04X %d' % (cp, fixed[cp]))


if __name__ == '__main__':
    main()
