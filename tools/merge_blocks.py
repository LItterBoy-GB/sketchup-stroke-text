"""Merge glyph blocks from one LFF font into another.

Used to combine the 256 px main batch with the 512 px batch (Latin extensions and
architectural annotation characters) into the shipped font. Blocks already present
in the target are replaced, so the command is idempotent; the target's existing
content keeps its original order and every byte before the first changed block.

Run after postprocess_symbols.py on both inputs and before make_superscript.py /
make_subscript.py.
"""
import argparse, re
from pathlib import Path


def split_blocks(text):
    """-> (header text, [(codepoint, body lines)])"""
    parts = re.split(r'(?m)^\[([0-9A-Fa-f]{1,6})\]\s*$', text)
    header = parts[0]
    blocks = []
    for i in range(1, len(parts), 2):
        rest = parts[i + 1]
        if rest.startswith('\n'):
            rest = rest[1:]
        blocks.append((int(parts[i], 16), ['[%s]' % parts[i]] + rest.split('\n')))
    return header, blocks


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--into', required=True)
    p.add_argument('--from', dest='source', required=True)
    p.add_argument('--out')
    a = p.parse_args()
    into, src, out = Path(a.into), Path(a.source), Path(a.out or a.into)

    target_text = into.read_text(encoding='utf8')
    header, target = split_blocks(target_text)
    _, extra = split_blocks(src.read_text(encoding='utf8'))

    by_cp = {cp: body for cp, body in target}
    order = [cp for cp, _ in target]
    replaced, added = [], []
    for cp, body in extra:
        if cp in by_cp:
            by_cp[cp] = body
            replaced.append(cp)
        else:
            by_cp[cp] = body
            order.append(cp)
            added.append(cp)

    chunks = ['\n'.join(by_cp[cp]).rstrip('\n') for cp in order]
    text = header.rstrip('\n') + '\n' + '\n\n'.join(chunks) + '\n'
    out.write_text(text, encoding='utf8', newline='\n')

    print('merged %d block(s): %d added, %d replaced; total %d'
          % (len(extra), len(added), len(replaced), len(order)))
    if added:
        print('  added:', ' '.join('U+%04X' % cp for cp in sorted(added)))


if __name__ == '__main__':
    main()
