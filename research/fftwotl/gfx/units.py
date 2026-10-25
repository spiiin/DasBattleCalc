"""Render the standing frames of the units of a battle RAM dump (research/fftwotl/ram0.bin).

Unit record (0x1E8 B, 21 at 0x092E5CB4): +0x181 sprite sheet id, +0x04 palette, +0x51 facing
(low 2 bits: 0 south, 1 west, 2 north, 3 east).
Standing pose = first frame of SEQ animation 6 (towards the camera, faces screen lower-left) and
7 (away, faces screen upper-left); the other two screen diagonals are the horizontal mirror.
"""
import os, sys
from PIL import Image, ImageDraw
import sprites as S

HERE = os.path.dirname(os.path.abspath(__file__))
RAM = os.path.join(HERE, '..', 'ram0.bin')
UNITS, UNIT_SIZE = 0x092E5CB4, 0x1E8
sys.path.insert(0, os.path.join(HERE, '..'))
from fftext import dec  # noqa: E402

STAND_FRONT, STAND_BACK = 6, 7


def standing_frames(sheet_id):
    """(sheet, shp frame index front, back) of a sheet id."""
    inf, sheet = S.load_sheet(sheet_id)
    seq = S.load_seq(inf['seq'])
    return inf, sheet, seq[STAND_FRONT][0][0], seq[STAND_BACK][0][0]


def unit(ram, i):
    o = UNITS - 0x08000000 + i * UNIT_SIZE
    r = ram[o:o + UNIT_SIZE]
    name = dec(r[0x14E:r.index(0xFE, 0x14E)])
    return dict(slot=i, sheet=r[0x181], palette=r[0x04], facing=r[0x51] & 3, job=r[0x03], name=name)


def main(n=11):
    ram = open(RAM, 'rb').read()
    cw, ch, sc = 64, 72, 3
    can = Image.new('RGBA', (cw * 4, ch * n), (80, 110, 80, 255))
    lines = []
    for i in range(n):
        u = unit(ram, i)
        inf, sheet, ff, fb = standing_frames(u['sheet'])
        shp = S.load_shp(inf['shp'])
        poses = [(ff, False), (ff, True), (fb, False), (fb, True)]
        for j, (k, m) in enumerate(poses):
            img = S.render_frame(sheet, shp.frames[k], u['palette'], mirror=m, size=(cw, ch),
                                 origin=(cw // 2, ch - 8))
            can.alpha_composite(img, (cw * j, ch * i))
        lines.append('%2d %-10s sheet %02X %-18s pal %d facing %d frames %d/%d' % (
            i, u['name'], u['sheet'], inf['name'], u['palette'], u['facing'], ff, fb))
    big = can.resize((can.width * sc, can.height * sc), Image.NEAREST)
    d = ImageDraw.Draw(big)
    for i, ln in enumerate(lines):
        d.text((4, ch * sc * i + 4), ln, fill=(255, 255, 0, 255))
    p = os.path.join(S.fp.OUT, 'units_standing.png')
    big.save(p)
    print('\n'.join(lines))
    print(p)


if __name__ == '__main__':
    main()
