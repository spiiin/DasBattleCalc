"""Battle map sprites from the ROM (research/notes.md, "Graphics").

python gfx_sprites.py rom.gba [<prefix>]
- gfx/sprites.png: the standing frame (animation 0, first frame) of every
  sprite set, palette row 0;
- with a gfx_probe prefix (EWRAM, OAM dumps of one frame and its OBJ
  layer rendered by gfx_obj8.py into <prefix>_obj.png): every unit's
  current frame from the ROM against the screen, pixel by pixel.
"""
import struct
import sys
from PIL import Image
import gfx_decode as g

rom = open(sys.argv[1], 'rb').read()
JOBS, CHARS, SETS = 0x08521A14, 0x085273D8, 0x08390E44
TILES, LAYOUTS, PALS = 0x0869B89C, 0x08852E7C, 0x08419D60
SIZES = {(0, 0): (8, 8), (0, 1): (16, 16), (0, 2): (32, 32), (0, 3): (64, 64),
         (1, 0): (16, 8), (1, 1): (32, 8), (1, 2): (32, 16), (1, 3): (64, 32),
         (2, 0): (8, 16), (2, 1): (8, 32), (2, 2): (16, 32), (2, 3): (32, 64)}

def r8(a):
    return rom[a - 0x08000000]

def r32(a):
    return struct.unpack_from('<I', rom, a - 0x08000000)[0]

def job_field(job, alt, field):
    for _ in range(16):
        parent = r8(JOBS + job * 52 + 5)
        if parent == 0xFF:
            job = alt
        elif parent:
            job = parent
        else:
            return r8(JOBS + job * 52 + field)
    raise ValueError("job chain")

def unit_sprite(rec):
    """Sprite set of a unit record: a story character's +0x04, else job +0x07."""
    if rec[4] > 1:
        return r8(CHARS + rec[4] * 14 + 4)
    return job_field(rec[5], rec[7], 0x07)

def sprite_count():
    n = 0
    while 0x08360000 <= r32(SETS + n * 4) < 0x08390000:
        n += 1
    return n

def anim_frames(sprite, anim):
    """Frames of an animation: (tile offset, layout offset) per 20-byte entry."""
    a = r32(r32(SETS + sprite * 4) + anim * 12)
    return [(r32(a + 4 + e * 20), r32(a + 8 + e * 20)) for e in range(r32(a))]

def layout(lay):
    """Pieces (x, y, w, h, tile) of a frame layout; x, y from the feet."""
    a = LAYOUTS + lay
    pieces = []
    for k in range(r8(a) | (r8(a + 1) << 8)):
        b = [r8(a + 2 + k * 6 + i) for i in range(6)]
        y = b[0] - 256 if b[0] >= 128 else b[0]
        x = b[2] | ((b[3] & 1) << 8)
        x = x - 512 if x >= 256 else x
        w, h = SIZES[(b[1] >> 6, b[3] >> 6)]
        pieces.append((x, y, w, h, b[4] | (b[5] << 8)))
    return pieces

def frame_image(tiles_off, lay, row, flip=False):
    """RGBA frame and the feet point (fx, fy) in it."""
    pcs = layout(lay)
    x0 = min(p[0] for p in pcs)
    y0 = min(p[1] for p in pcs)
    w = max(p[0] + p[2] for p in pcs) - x0
    h = max(p[1] + p[3] for p in pcs) - y0
    pal = g.palette(rom, PALS - 0x08000000 + row * 32, 16)
    base = TILES - 0x08000000 + tiles_off
    img = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    for px, py, pw, ph, t0 in pcs:
        for y in range(ph):
            for x in range(pw):
                t = t0 + (y // 8) * (pw // 8) + x // 8
                b = rom[base + t * 32 + (y % 8) * 4 + (x % 8) // 2]
                c = (b >> 4) if x & 1 else b & 15
                if c:
                    img.putpixel((px - x0 + x, py - y0 + y), pal[c] + (255,))
    if flip:
        return img.transpose(Image.FLIP_LEFT_RIGHT), (x0 + w, -y0)
    return img, (-x0, -y0)

def standing(sprite, facing, row):
    """The first frame of the standing animation for a facing (0..3)."""
    off, lay = anim_frames(sprite, 0 if facing in (0, 3) else 1)[0]
    return frame_image(off, lay, row, flip=facing in (2, 3))

if __name__ == '__main__':
    n = sprite_count()
    sheet = Image.new('RGBA', (16 * 36, ((n + 15) // 16) * 52), (60, 60, 70, 255))
    for s in range(n):
        try:
            im, _ = standing(s, 0, 0)
            sheet.alpha_composite(im.crop((0, 0, min(im.width, 34), min(im.height, 50))),
                                  ((s % 16) * 36 + 1, (s // 16) * 52 + 1))
        except Exception as e:      # noqa: BLE001 - a research sheet
            print("sprite", s, e)
    sheet.resize((sheet.width * 2, sheet.height * 2), Image.NEAREST).save('gfx/sprites.png')
    print("sprite sets", n)

    if len(sys.argv) > 2:
        pre = sys.argv[2]
        ew = open(pre + '_ewram.bin', 'rb').read()
        oam = open(pre + '_oam.bin', 'rb').read()
        scr = Image.open(pre + '_obj.png').convert('RGB').resize((240, 160), Image.NEAREST)
        for k in range(12):
            w = 0x223AC + k * 0x90
            rec = struct.unpack_from('<I', ew, w)[0]
            if not 0x02000000 <= rec < 0x02040000:
                break
            u = ew[rec - 0x02000000: rec - 0x02000000 + 0x108]
            if u[5] == 0:
                continue
            obj = struct.unpack_from('<I', ew, w + 0x44)[0] - 0x02000000
            cur = struct.unpack_from('<I', ew, obj + 0x20)[0]
            lay = struct.unpack_from('<I', ew, obj + 0x2C)[0] - LAYOUTS
            tile = struct.unpack_from('<H', ew, obj + 0x12)[0]
            row, facing = ew[w + 0x1E], ew[w + 0x1F]
            sprite = unit_sprite(u)
            in_set = any(cur == f for a in (0, 1) for f, _ in anim_frames(sprite, a))
            # the OAM piece with the frame's tile 0 places the frame on screen
            pos = None
            for i in range(128):
                a0, a1, a2 = struct.unpack_from('<HHH', oam, i * 8)
                if (a0 >> 8) & 3 != 2 and (a2 & 0x3FF) == tile:
                    pos = (a1 & 0x1FF, a0 & 0xFF, (a1 >> 12) & 1)
                    break
            if pos is None:
                print("%08X sprite %3d: not on screen" % (rec, sprite))
                continue
            im, (fx, fy) = frame_image(cur, lay, row, flip=bool(pos[2]))
            # align the image's piece 0 with its OAM sprite
            p0 = layout(lay)[0]
            px = (fx + p0[0]) if not pos[2] else (fx - p0[0] - p0[2])
            py = fy + p0[1]
            ox, oy = pos[0] - px, pos[1] - py
            diff = total = 0
            for y in range(im.height):
                for x in range(im.width):
                    p = im.getpixel((x, y))
                    X, Y = ox + x, oy + y
                    if p[3] and 0 <= X < 240 and 0 <= Y < 160:
                        total += 1
                        diff += tuple(v >> 3 for v in scr.getpixel((X, Y))) != tuple(v >> 3 for v in p[:3])
            print("%08X sprite %3d facing %d row %2d frame %06X layout %04X%s: %d of %d pixels differ" % (
                rec, sprite, facing, row, cur, lay, "" if in_set else " (not a standing frame)", diff, total))
