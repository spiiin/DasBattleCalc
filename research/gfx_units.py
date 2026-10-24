"""Battle map sprites of the units of a battle (research/notes.md, "Graphics").

python gfx_units.py rom.gba <prefix>   (prefix: gfx/b1_005 - gfx_probe dumps
with EWRAM; the frame's VRAM / OAM / palette dumps of the same prefix)

For every unit: sprite id (job +0x07 through the parent chain), its
animation set, which OBJ VRAM slot shows a frame of that set and with
which palette row (OAM), plus team / race for finding the palette rule.
"""
import struct
import sys

rom = open(sys.argv[1], 'rb').read()
pre = sys.argv[2]
ew = open(pre + '_ewram.bin', 'rb').read()
vram = open(pre + '_vram.bin', 'rb').read()
oam = open(pre + '_oam.bin', 'rb').read()
JOBS, SETS, BLOB = 0x08521A14, 0x08390E44, 0x0869B89C

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

def set_frames(sprite):
    """Frame offsets (from BLOB) of all animations of a sprite's set."""
    base = r32(SETS + sprite * 4)
    frames = set()
    for k in range(84):
        anim = r32(base + k * 12)
        if not 0x08000000 <= anim < 0x09000000:
            continue
        a = anim
        n = r32(a)
        if n > 64:
            continue
        for e in range(n):
            frames.add(r32(a + 4 + e * 20))
    return frames

# OBJ VRAM tile -> a frame offset, when a frame of the blob starts there
# (64 bytes = the frame's first two tiles must match)
blob = rom[BLOB - 0x08000000:]
slots = {}
for t in range(1024):
    data = vram[0x10000 + t * 32: 0x10000 + t * 32 + 64]
    if len(set(data)) <= 2:
        continue
    at = blob.find(data)
    if at >= 0 and at % 32 == 0:
        slots[t] = at

# tile -> palette rows from OAM (visible sprites starting at that tile)
rows = {}
for i in range(128):
    a0, a1, a2 = struct.unpack_from('<HHH', oam, i * 8)
    if (a0 >> 8) & 3 == 2:
        continue
    rows.setdefault(a2 & 0x3FF, set()).add(a2 >> 12)

for k in range(12):
    rec = struct.unpack_from('<I', ew, 0x223AC + k * 0x90)[0]
    if not 0x02000000 <= rec < 0x02040000:
        break
    u = ew[rec - 0x02000000: rec - 0x02000000 + 0x108]
    if u[5] == 0:
        continue
    flags = struct.unpack_from('<H', u, 0x28)[0]
    sprite = r8(0x085273D8 + u[4] * 14 + 4) if u[4] > 1 else job_field(u[5], u[7], 0x07)
    frames = set_frames(sprite)
    shown = [s for s, f in slots.items() if f in frames]
    print("%08X char %3d job %3d +7 %3d race(job+4) %d flags %04X sprite %3d set %08X slots %s rows %s" % (
        rec, u[4], u[5], u[7], r8(JOBS + u[5] * 52 + 4), flags, sprite, r32(SETS + sprite * 4),
        shown, [sorted(rows.get(s, [])) for s in shown]))
