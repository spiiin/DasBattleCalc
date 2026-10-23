"""DasBattleCalc icons: 16 x 16 pixel art in the spirit of FFTA's GBA
menus (dark outline, warm palette). Our own drawings, same license as
the project. Writes ffta_icons16.png (the sheet the app loads) and
ffta_icons_preview.png (x4, on the UI grey, for looking at).

Sheet layout as before (native/imgui_ext.cpp icon_uv): cell (ix, iy) at
x = 5 + 21 * ix, y = 10 + 21 * iy; icon id = ix | iy << 8.
The ids are in scripts/ui/icons.das - keep the ICONS order in sync.

    python assets/icons/make_icons.py
"""
import math
import os
from PIL import Image

PAL = {
    'K': (40, 30, 48),      # outline
    'W': (248, 248, 236),   # white
    'Y': (240, 192, 64),    # gold
    'y': (176, 120, 32),
    'B': (72, 120, 216),    # blue
    'b': (40, 64, 144),
    'L': (152, 200, 248),   # light blue
    'R': (216, 64, 56),     # red
    'r': (136, 32, 32),
    'G': (96, 184, 72),     # green
    'g': (40, 104, 40),
    'H': (168, 224, 120),   # light green
    'S': (192, 200, 208),   # steel
    's': (112, 120, 136),
    'P': (240, 224, 176),   # parchment
    'p': (192, 160, 104),
    'N': (152, 96, 48),     # brown
    'n': (96, 56, 24),
    'C': (112, 224, 208),   # crystal
    'c': (48, 152, 168),
}


def grid():
    return [['.'] * 16 for _ in range(16)]


def from_rows(rows):
    g = grid()
    for y, row in enumerate(rows):
        for x, ch in enumerate(row[:16]):
            g[y][x] = ch
    return g


def outline(g):
    """Dark outline around the filled pixels (4 neighbours)."""
    out = [row[:] for row in g]
    for y in range(16):
        for x in range(16):
            if g[y][x] != '.':
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < 16 and 0 <= ny < 16 and g[ny][nx] != '.':
                    out[y][x] = 'K'
                    break
    return out


# ------------------------------------------------------------ drawings

def info():
    g = grid()
    for y in range(16):
        for x in range(16):
            d = math.hypot(x - 7.5, y - 7.5)
            if d <= 6.2:
                g[y][x] = 'L' if (x + y < 10 and d > 3.5) else ('b' if x + y > 20 else 'B')
    for x, y in ((7, 3), (8, 3), (7, 4), (8, 4)):
        g[y][x] = 'W'
    for y in range(6, 12):
        g[y][7] = g[y][8] = 'W'
    g[6][6] = 'W'
    for x in range(6, 10):
        g[11][x] = 'W'
    return outline(g)


def hourglass():
    return outline(from_rows([
        "................",
        "..nNNNNNNNNNNn..",
        "...LWWWWWWWWL...",
        "...LYYYYYYYYL...",
        "....LYYYYYYL....",
        ".....LYYYYL.....",
        "......LYYL......",
        ".......YY.......",
        "......LWYL......",
        ".....LWWYWL.....",
        "....LWWWYWWL....",
        "...LWWYYYYWWL...",
        "...LYYYYYYYYL...",
        "..nNNNNNNNNNNn..",
        "................",
        "................",
    ]))


def sword():
    g = grid()
    for i in range(7):
        g[2 + i][12 - i] = 'W'
        g[2 + i][13 - i] = 'S'
    g[1][13] = 'W'
    for x, y in ((4, 7), (5, 8), (6, 9), (7, 10), (8, 11)):
        g[y][x] = 'Y'
    g[7][4] = g[11][8] = 'y'
    for x, y in ((5, 10), (4, 11), (3, 12)):
        g[y][x] = 'N'
    g[13][2] = 'Y'
    return outline(g)


def helmet(enemy):
    band = 'R' if enemy else 'B'
    top = "................" if enemy else ".......YY......."
    rows = [
        "................",
        top,
        "......YYYY......" if not enemy else "................",
        ".......YY......." if not enemy else "................",
        ".....SSSSSS.....",
        "...SSWWSSSSSS...",
        "..SSWSSSSSSSSs..",
        "..SWSSSSSSSSSs..",
        "..XXXXXXXXXXXx..".replace('X', band).replace('x', 'r' if enemy else 'b'),
        "..SSKKSSSSKKSs..",
        "..SSSSSSSSSSSs..",
        "...SSSSKSSSSs...",
        "...sSSSKSSSss...",
        "....ssssssss....",
        "................",
        "................",
    ]
    g = from_rows(rows)
    if enemy:   # horns
        for x, y in ((1, 2), (1, 3), (2, 4), (2, 5), (14, 2), (14, 3), (13, 4), (13, 5)):
            g[y][x] = 'Y'
        g[2][1] = g[2][14] = 'W'
        for y in range(4, 14):
            for x in range(16):
                if g[y][x] == 'S':
                    g[y][x] = 's' if (x + y) % 5 == 0 else 'S'
    return outline(g)


def book():
    return outline(from_rows([
        "................",
        "................",
        "...RRRRRRRRRR...",
        "...RYRRRRRRrW...",
        "...RRRRRRRRrW...",
        "...RRRYYYRRrW...",
        "...RRRYRYRRrW...",
        "...RRRYYYRRrW...",
        "...RRRRRRRRrW...",
        "...RRRRRRRRrW...",
        "...RRRRRRRRrW...",
        "...RYRRRRRRrW...",
        "...rrrrrrrrrW...",
        "....PPPPPPPPP...",
        "................",
        "................",
    ]))


def flag():
    return outline(from_rows([
        "................",
        "..Y.............",
        "..NBBBBBBBBB....",
        "..NBBBBBBBBBB...",
        "..NBBBBYYBBBB...",
        "..NBBBYYYYBBB...",
        "..NBBBBYYBBBB...",
        "..NBBBBBBBBB....",
        "..NbbbbbbbbB....",
        "..N.............",
        "..N.............",
        "..N.............",
        "..N.............",
        "..N.............",
        ".nNn............",
        "................",
    ]))


def magnifier():
    g = grid()
    for y in range(16):
        for x in range(16):
            d = math.hypot(x - 6, y - 6)
            if d <= 2.6:
                g[y][x] = 'W' if (x < 6 and y < 6) else 'L'
            elif d <= 4.4:
                g[y][x] = 'S' if x + y < 12 else 's'
    for i in range(4):
        g[9 + i][9 + i] = 'N'
        g[10 + i][9 + i] = 'n'
    return outline(g)


def crystal():
    g = grid()
    for y in range(16):
        for x in range(16):
            v = abs(x - 7.5) / 6.0 + abs(y - 7.5) / 7.0
            if v <= 1.0:
                g[y][x] = 'C' if x < 8 else 'c'
    for y in range(3, 8):
        x = 7 - (y - 3) // 2
        g[y][x] = 'W'
    for x in range(3, 13):
        if g[7][x] != '.':
            g[7][x] = 'L' if x < 8 else 'C'
    return outline(g)


def iso_block():
    """FFTA's isometric map tile: grass top, earth sides."""
    g = grid()
    for x in range(16):
        bottom = -1
        for y in range(16):
            v = abs(x - 7.5) / 7.0 + abs(y - 5.0) / 3.6
            if v <= 1.0:
                g[y][x] = 'H' if (y < 5 and x < 8 and v > 0.6) else 'G'
                bottom = y
        if bottom >= 0:
            for y in range(bottom + 1, min(16, bottom + 5)):
                g[y][x] = 'N' if x < 8 else 'n'
    for x in range(16):   # a seam on the top face
        y = 5
        if g[y][x] == 'G' and x in (7, 8):
            g[y][x] = 'g'
    return outline(g)


def screen():
    return outline(from_rows([
        "................",
        "................",
        ".ssssssssssssss.",
        ".sLLLLLLLLLLLLs.",
        ".sLLLLLLLLYYLLs.",
        ".sLLLLLLLLYYLLs.",
        ".sLLLLLLLLLLLLs.",
        ".sLLLLGGLLLLLLs.",
        ".sLLLGGGGLLGGLs.",
        ".sGGGGGGGGGGGGs.",
        ".sggggggggggggs.",
        ".ssssssssssssss.",
        "......ssss......",
        "....ssssssss....",
        "................",
        "................",
    ]))


def refresh():
    g = grid()
    for y in range(16):
        for x in range(16):
            d = math.hypot(x - 7.5, y - 8.0)
            a = math.degrees(math.atan2(8.0 - y, x - 7.5)) % 360
            if 3.4 <= d <= 5.4 and not (15 <= a <= 80):
                g[y][x] = 'G' if 90 <= a <= 270 else 'g'
    # the head at the top end of the ring, pointing right (clockwise)
    for x, y0, y1 in ((8, 0, 6), (9, 1, 5), (10, 2, 4), (11, 3, 3)):
        for y in range(y0, y1 + 1):
            g[y][x] = 'H'
    return outline(g)


def curved(clockwise):
    """An arc over the top, the head at the left end pointing down."""
    g = grid()
    for y in range(16):
        for x in range(16):
            d = math.hypot(x - 8.5, y - 10.0)
            if 3.5 <= d <= 5.6 and y <= 9:
                g[y][x] = 'Y' if y < 7 else 'y'
    for y, x0, x1 in ((9, 1, 7), (10, 2, 6), (11, 3, 5), (12, 4, 4)):
        for x in range(x0, x1 + 1):
            g[y][x] = 'Y'
    if clockwise:
        g = [row[::-1] for row in g]
    return outline(g)


def scroll_out():
    g = from_rows([
        "................",
        "..ppppppppp.....",
        "..PPPPPPPPP.....",
        "..PnnnnnnPP.....",
        "..PPPPPPPPP.....",
        "..PnnnnnPPP.....",
        "..PPPPPP........",
        "..PnnnnP........",
        "..PPPPPP........",
        "..PnnnnnPPP.....",
        "..PPPPPPPPP.....",
        "..PnnnnnnPP.....",
        "..PPPPPPPPP.....",
        "..ppppppppp.....",
        "................",
        "................",
    ])
    for x in range(8, 13):
        g[7][x] = 'Y'
    for x, y in ((12, 5), (13, 6), (14, 7), (13, 8), (12, 9), (12, 6), (12, 8), (13, 7), (12, 7)):
        g[y][x] = 'Y'
    return outline(g)


def corners():
    g = grid()
    for a, b in ((1, 1), (14, 1), (1, 14), (14, 14)):
        sx = 1 if a < 8 else -1
        sy = 1 if b < 8 else -1
        for i in range(4):
            g[b][a + sx * i] = 'Y'
            g[b + sy * i][a] = 'Y'
    for y in range(6, 10):
        for x in range(6, 10):
            g[y][x] = 'S'
    g[6][6] = 'W'
    return outline(g)


def triangle(down):
    g = grid()
    for i in range(4):
        for j in range(-3 + i, 4 - i):
            if down:
                g[6 + i][8 + j] = 'Y' if i < 2 else 'y'
            else:
                g[8 + j][6 + i] = 'Y' if i < 2 else 'y'
    return outline(g)


# order = ids in scripts/ui/icons.das (6 per row)
ICONS = [
    ('info', info()), ('turns', hourglass()), ('attack', sword()), ('unit', helmet(False)),
    ('enemy', helmet(True)), ('game', book()),
    ('roster', flag()), ('inspector', magnifier()), ('calc', crystal()), ('field', iso_block()),
    ('screen', screen()), ('load', refresh()),
    ('turn_ccw', curved(False)), ('turn_cw', curved(True)), ('export', scroll_out()), ('fit', corners()),
    ('open', triangle(True)), ('closed', triangle(False)),
]


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    cols = 6
    rows = (len(ICONS) + cols - 1) // cols
    sheet = Image.new('RGBA', (5 + 21 * cols, 10 + 21 * rows), (0, 0, 0, 0))
    preview = Image.new('RGBA', (cols * 80, rows * 80), (114, 114, 114, 255))
    for i, (_, g) in enumerate(ICONS):
        ix, iy = i % cols, i // cols
        tile = Image.new('RGBA', (16, 16), (0, 0, 0, 0))
        for y in range(16):
            for x in range(16):
                if g[y][x] != '.':
                    tile.putpixel((x, y), PAL[g[y][x]] + (255,))
        sheet.paste(tile, (5 + 21 * ix, 10 + 21 * iy))
        preview.alpha_composite(tile.resize((64, 64), Image.NEAREST), (ix * 80 + 8, iy * 80 + 8))
    sheet.save(os.path.join(here, 'ffta_icons16.png'))
    preview.save(os.path.join(here, 'ffta_icons_preview.png'))
    for i, (name, _) in enumerate(ICONS):
        # decimal: hex literals are uint in daslang, the icon is an int
        print(f"let ICON_{name.upper()} = {(i // cols) << 8 | (i % cols)}    // ({i % cols}, {i // cols})")


if __name__ == '__main__':
    main()
