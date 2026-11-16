"""Add superscript digits 0-9 to a finalized LFF font, then refresh full-summary.json.

The source Noto Sans CJK SC has real superscripts for 1 2 3 4 5 6 7 8 but not for
0 and 9, so shipping a mix would look inconsistent. All ten are therefore
synthesized from the plain digit glyphs: scale 0.5, anchored at the top-left
corner of the digit ink box, which makes each one occupy exactly the top-left
quarter of the original digit. The advance is copied from the digit so
"10³" / "m²" / "建筑²层" read as continuous text.

Run after finalize_font.py. Idempotent: existing blocks for these ten
codepoints are replaced, not duplicated.
"""
import argparse, hashlib, json, re
from pathlib import Path

SCALE = 0.5
SLOTS = [(0x00B2, '2'), (0x00B3, '3'), (0x00B9, '1'), (0x2070, '0')] + [(0x2074 + i, str(4 + i)) for i in range(6)]

root = Path(__file__).resolve().parent
p = argparse.ArgumentParser()
p.add_argument('--lff', default=str(root / 'fonts/hei-improved.lff'))
p.add_argument('--summary', default=str(root / 'full-summary.json'))
a = p.parse_args()
lff, summary = Path(a.lff), Path(a.summary)


def split_blocks(text):
    """-> (header lines, [(codepoint, body lines)])"""
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


def points(line):
    out = []
    for part in line.strip().split(';'):
        v = part.split(',')
        out.append((float(v[0]), float(v[1]), v[2] if len(v) > 2 else ''))
    return out


def advance(body):
    for line in body:
        m = re.match(r'^#\s*Advance:\s*([0-9.]+)', line.strip())
        if m:
            return float(m.group(1))
    raise ValueError('block has no "# Advance:" line')


text = lff.read_text(encoding='utf8')
header, blocks = split_blocks(text)
by_cp = {cp: body for cp, body in blocks}
dropped = [cp for cp in by_cp if cp in dict(SLOTS)]
for cp in dropped:
    del by_cp[cp]

new = []
for target, digit in SLOTS:
    src = by_cp[ord(digit)]
    geo = [line for line in src if is_geom(line)]
    pts = [q for line in geo for q in points(line)]
    xmin, ymax = min(q[0] for q in pts), max(q[1] for q in pts)
    body = ['[%04X]' % target, '# Advance: %.8f' % advance(src)]
    for line in geo:
        body.append(';'.join('%.6f,%.6f%s' % (xmin + (x - xmin) * SCALE, ymax - (ymax - y) * SCALE, ',' + b if b else '')
                             for x, y, b in points(line)))
    new.append((target, body))

chunks = []
for cp, body in blocks:                      # keep original order, minus replaced blocks
    if cp in dict(SLOTS):
        continue
    chunks.append('\n'.join(body).rstrip('\n'))
for cp, body in sorted(new):                 # append synthesized glyphs, like earlier additions
    chunks.append('\n'.join(body).rstrip('\n'))
out = '\n'.join(header).rstrip('\n') + '\n' + '\n\n'.join(chunks) + '\n'
lff.write_text(out, encoding='utf8', newline='\n')

_, final_blocks = split_blocks(lff.read_text(encoding='utf8'))
nonempty = sum(1 for cp, body in final_blocks if any(is_geom(l) for l in body))
segments = sum(len(points(l)) - 1 for cp, body in final_blocks for l in body if is_geom(l))

data = json.loads(summary.read_text(encoding='utf8'))
data['font_sha256'] = hashlib.sha256(lff.read_bytes()).hexdigest()
data['glyph_records'] = len(final_blocks)
data['nonempty_glyphs'] = nonempty
data['generated_segments'] = segments
data['superscript_generated'] = {
    'codepoints': ['U+%04X' % cp for cp, _ in sorted(new)],
    'source_digits': 'U+0030-U+0039',
    'scale': SCALE,
    'anchor': 'top-left corner of the source digit ink box',
    'advance': 'same as the source digit (%.8f)' % advance(by_cp[ord('0')]),
    'added_paths': sum(sum(1 for l in body if is_geom(l)) for _, body in new),
    'added_segments': sum(len(points(l)) - 1 for _, body in new for l in body if is_geom(l)),
    'reason': 'source font lacks U+2070 and U+2079, so all ten are derived from the digits to stay consistent',
}
summary.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf8', newline='\n')
print('replaced %d existing block(s); wrote %d glyphs, %d segments' % (len(dropped), len(final_blocks), segments))
