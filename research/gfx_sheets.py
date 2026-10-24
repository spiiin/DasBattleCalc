"""Portraits and item icons straight from the ROM (research/notes.md, "Graphics").

python gfx_sheets.py rom.gba [ewram.bin shot.png]
- gfx/portraits.png: all 103 portraits (ally palettes when known);
- gfx/icons.png: all 522 item icons with their palettes;
- with a battle's EWRAM and a screenshot of its HUD (gfx_probe frame 30):
  checks the portrait of the unit whose turn it is pixel by pixel.
"""
import struct
import sys
from PIL import Image
import gfx_decode as g

rom = open(sys.argv[1], 'rb').read()
JOBS, CHARS = 0x08521A14, 0x085273D8
PORTRAITS, LAYOUTS, PALETTES = 0x083E105C, 0x08417F88, 0x083D5A1C
ICONS, ICON_PAL_INDEX, ICON_PALETTES = 0x083C83FC, 0x083C7FE4, 0x0841A100

def r8(a):
    return rom[a - 0x08000000]

def table(t, i):
    o = t - 0x08000000
    if rom[o] == 2:
        return t + 4 + struct.unpack_from('<H', rom, o + 4 + i * 2)[0]
    return t + 4 + struct.unpack_from('<I', rom, o + 4 + i * 4)[0]

def job_field(job, alt, field):
    """0x080C8570: follow the job's parent (+0x05; 0xFF: the unit's +0x07)."""
    for _ in range(16):
        parent = r8(JOBS + job * 52 + 5)
        if parent == 0xFF:
            job = alt
        elif parent:
            job = parent
        else:
            return r8(JOBS + job * 52 + field)
    raise ValueError("job chain")

def unit_portrait(rec):
    """(portrait, palette) of a unit record (bytes): 0x080CB868, 0x080CB7C0."""
    char, job, alt = rec[4], rec[5], rec[7]
    enemy = struct.unpack_from('<H', rec, 0x28)[0] & 0x8000
    if char > 1:
        c = CHARS + char * 14
        return r8(c + 0x0B), r8(c + (0x0D if enemy else 0x0C))
    return job_field(job, alt, 0x0D), job_field(job, alt, 0x0F if enemy else 0x0E)

def portrait_image(pid, palid, flip=False):
    tiles = g.lzss(rom, table(PORTRAITS, pid))
    cols = g.a7(rom, PALETTES, palid)                  # OBJ colours 96..143
    pal = [g.bgr555(struct.unpack_from('<H', cols, i * 2)[0]) for i in range(len(cols) // 2)]
    lay = table(LAYOUTS, pid) - 0x08000000
    img = Image.new('RGBA', (64, 88), (0, 0, 0, 0))
    px = img.load()
    SIZES = {(0, 0): (8, 8), (0, 1): (16, 16), (0, 2): (32, 32), (0, 3): (64, 64),
             (1, 0): (16, 8), (1, 1): (32, 8), (1, 2): (32, 16), (1, 3): (64, 32),
             (2, 0): (8, 16), (2, 1): (8, 32), (2, 2): (16, 32), (2, 3): (32, 64)}
    for k in range(rom[lay]):
        b = rom[lay + 2 + k * 6: lay + 8 + k * 6]
        y = b[0] - 256 if b[0] >= 128 else b[0]
        x = b[2] | ((b[3] & 1) << 8)
        x = x - 512 if x >= 256 else x
        w, h = SIZES[(b[1] >> 6, b[3] >> 6)]
        tile = b[4] | (b[5] << 8)
        for yy in range(h):
            for xx in range(w):
                t = (yy // 8) * (w // 8) + xx // 8
                c = tiles[tile * 32 + t * 64 + (yy % 8) * 8 + xx % 8]
                if c:
                    px[64 + x + xx, 88 + y + yy] = pal[c - 96] + (255,)
    return img.transpose(Image.FLIP_LEFT_RIGHT) if flip else img

def icon_image(item):
    data = g.a7(rom, ICONS, item)
    k = rom[ICON_PAL_INDEX - 0x08000000 + 4 + item * 2] >> 4
    pal = g.palette(rom, ICON_PALETTES - 0x08000000 + k * 32, 16)
    img = Image.new('RGBA', (16, 16))
    rows = g.tiles(data, pal, 2, 2)
    for y in range(16):
        for x in range(16):
            img.putpixel((x, y), rows[y][x])
    return img

# portrait palettes for the sheet: the first ally palette that names it
first_pal = {}
for c in range(256):
    a = CHARS + c * 14
    if a + 14 > 0x08000000 + len(rom) or c > 120:
        break
    first_pal.setdefault(r8(a + 0x0B), r8(a + 0x0C))
for j in range(170):
    try:
        first_pal.setdefault(job_field(j, j, 0x0D), job_field(j, j, 0x0E))
    except (ValueError, IndexError):
        pass

n = struct.unpack_from('<H', rom, PORTRAITS - 0x08000000 + 2)[0]
sheet = Image.new('RGBA', (16 * 64, ((n + 15) // 16) * 88), (60, 60, 70, 255))
for p in range(n):
    try:
        im = portrait_image(p, first_pal.get(p, 0))
        sheet.alpha_composite(im, ((p % 16) * 64, (p // 16) * 88))
    except Exception as e:      # noqa: BLE001 - a research sheet: show what decodes
        print("portrait", p, e)
sheet.save('gfx/portraits.png')

m = g.a7_count(rom, ICONS)
isheet = Image.new('RGBA', (32 * 18, ((m + 31) // 32) * 18), (60, 60, 70, 255))
for i in range(m):
    isheet.alpha_composite(icon_image(i), ((i % 32) * 18 + 1, (i // 32) * 18 + 1))
isheet.resize((isheet.width * 2, isheet.height * 2), Image.NEAREST).save('gfx/icons.png')
print("portraits", n, "icons", m)

if len(sys.argv) > 3:
    ew = open(sys.argv[2], 'rb').read()
    shot = Image.open(sys.argv[3]).convert('RGB')
    rec = ew[0x80:0x80 + 0x108]                        # Marc, the first battle's actor
    pid, palid = unit_portrait(rec)
    im = portrait_image(pid, palid, flip=True)          # the HUD shows it mirrored
    # HUD (OAM, frame 30): the 32x64 piece at x 0, y 88 -> image origin (0, 64)
    diff = total = 0
    for y in range(88):
        for x in range(64):
            p = im.getpixel((x, y))
            sy = 64 + y
            if p[3] and sy < 160:
                total += 1
                diff += shot.getpixel((x, sy)) != p[:3]
    print("Marc portrait %d palette %02X: %d of %d pixels differ" % (pid, palid, diff, total))
