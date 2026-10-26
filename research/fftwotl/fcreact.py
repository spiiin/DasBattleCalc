# Reactions in the game: does a reaction trigger, and what does it do?
# Ramza (record 0) attacks Lezalas (record 5) - the action is performed.
# Lezalas gets one reaction (its bit in the record's mask +0x95.., the
# reaction id at +0x14), Brave 100 (the roll always passes), no shield and
# no class evade (the blow always lands). Cases may set his HP (the
# Critical reactions) or give Ramza a set (Rush for Counter Tackle, Fire
# for the magick ones). After the action: both units' HP, MP, CT, Brave,
# Faith, PA, MA, statuses. Output: react1.txt
#   "<reaction id> | <case> | <edits> | att <hp mp ct br fa pa ma st> | tgt <...> | tgt0 <...>"
import sys, struct
import fcprobe as P

A, T = 0, 5
REC = P.rec


def mask(rid):
    n = rid - 0x1A6
    return (REC(T) + 0x95 + n // 8, 0x80 >> (n % 8))


def snap(u):
    b = P.d.read(REC(u), P.SZ)
    hp, mp = struct.unpack_from('<H', b, 0x30)[0], struct.unpack_from('<H', b, 0x34)[0]
    return '%d %d %d %d %d %d %d %s' % (hp, mp, b[0x41], b[0x2B], b[0x2D], b[0x3E], b[0x3F], b[0x62:0x67].hex())


ATTACK = ['Y', 'S', 'H', 'H', 'sleep:0.6', 'H', 'sleep:0.8', 'W', 'sleep:0.6', 'H', 'sleep:1.2']
# Act, the secondary (index 2), its first ability, the help box, Lezalas
SECOND = ['Y', 'S', 'H', 'S', 'S', 'H', 'sleep:0.8', 'H', 'sleep:0.8', 'H', 'sleep:0.6', 'W', 'sleep:0.6', 'H',
          'sleep:1.2']
RUSH = ['Y', 'S', 'H', 'S', 'H', 'sleep:0.6', 'S', 'H', 'sleep:0.8', 'H', 'sleep:0.6', 'W', 'sleep:0.6', 'H',
        'sleep:1.2']                                   # Mettle, Rush (the second entry)
FIRE = [(REC(A) + 0x13, bytes([11])), (REC(A) + 0xA3 + 18, bytes([0xFF, 0xFF, 0xFF]))]
METTLE = [(REC(A) + 0xA3, bytes([0xFF, 0xFF, 0xFF]))]
BASE = [(REC(T) + 0x2B, bytes([100])), (REC(T) + 0x26, struct.pack('<H', 0xFF)), (REC(T) + 0x4B, bytes([0]))]
# Act, Arithmeticks, (help) Level, (help) multiple of 3, (help) Fire
ARITH = ['Y', 'S', 'H', 'sleep:0.4', 'S', 'S', 'H', 'sleep:0.8', 'H', 'sleep:0.8', 'S', 'H', 'sleep:0.8', 'H',
         'sleep:0.8', 'S', 'S', 'S', 'H', 'sleep:0.8', 'H', 'sleep:0.8', 'H', 'sleep:1.5']
ARITHSET = [(REC(A) + 0x13, bytes([21])), (REC(A) + 0xA3 + 48, bytes([0xFF, 0xFF, 0xFF])),
            (REC(A) + 0xA3 + 18, bytes([0xFF, 0xFF, 0xFF]))]
CASES = [
    # (reaction id, case, keys, extra setup)
    (442, 'attack', ATTACK, []),                         # Counter
    (453, 'attack', ATTACK, []),                         # First Strike
    (436, 'attack', ATTACK, []),                         # Counter Tackle: Attack (no)
    (436, 'rush', RUSH, METTLE),                         # Counter Tackle: Rush
    (427, 'attack', ATTACK, []),                         # Dragonheart
    (429, 'attack', ATTACK, [(REC(T) + 0x2B, bytes([90]))]),   # Bravery Boost (Brave 90: room for +3)
    (425, 'attack', ATTACK, []),                         # Vanish
    (428, 'attack', ATTACK, []),                         # Regenerate
    (422, 'attack', ATTACK, []),                         # Fury
    (423, 'attack', ATTACK, []),                         # Magick Boost
    (441, 'attack', ATTACK, []),                         # Auto-Potion
    (445, 'attack', ATTACK, []),                         # Mana Shield
    (431, 'critical', ATTACK, [(REC(T) + 0x30, struct.pack('<H', 50))]),   # Critical: Recover HP (50 - 49)
    (431, 'not_critical', ATTACK, []),
    (433, 'critical', ATTACK, [(REC(T) + 0x30, struct.pack('<H', 50))]),   # Critical: Quick
    (432, 'critical', ATTACK, [(REC(T) + 0x30, struct.pack('<H', 50))]),   # Critical: Recover MP
    (434, 'critical', ATTACK, [(REC(T) + 0x30, struct.pack('<H', 50))]),   # Bonecrusher
    (430, 'fire', SECOND, FIRE),                         # Faith Boost
    (430, 'attack', ATTACK, []),
    (438, 'fire', SECOND, FIRE),                         # Absorb MP
    (435, 'fire', SECOND, FIRE),                         # Magick Counter
    (0, 'none', ATTACK, []),                             # no reaction: the control
    # the magick ones need a magick that lands now: Arithmeticks (Level x 3,
    # Fire: Ramza, Lavian, Lezalas, Diesch); MP 5 for the Recover MP one
    (432, 'critical_mp5', ATTACK, [(REC(T) + 0x30, struct.pack('<H', 50)), (REC(T) + 0x34, struct.pack('<H', 5))]),
    (430, 'arith', ARITH, ARITHSET),                     # Faith Boost
    (438, 'arith', ARITH, ARITHSET),                     # Absorb MP
    (435, 'arith', ARITH, ARITHSET),                     # Magick Counter
    (440, 'arith', ARITH, ARITHSET),                     # Reflect (the reaction)
    (0, 'arith', ARITH, ARITHSET),                       # the control
    (0, 'rush', RUSH, METTLE),                           # the control of Rush
]
only = [a for a in sys.argv[1:] if not a.startswith('--')]
out = open('react1.txt', 'a' if only else 'w')
for rid, case, keys, extra in CASES:
    if only and '%d' % rid not in only:
        continue
    setup = BASE + extra
    if rid:
        a, bit = mask(rid)
        setup = setup + [(REC(T) + 0x14, struct.pack('<H', rid)), (a, bytes([bit]))]
    P.SETUP = setup
    P.FRESH = keys
    P.restart()
    t0 = snap(T)
    P.keys(['H', 'sleep:1.0', 'H', 'sleep:16'])        # the forecast, Perform
    line = '%d | %s | %s | att %s | tgt %s | tgt0 %s' % (rid, case, ' '.join('%x=%s' % (a, b.hex()) for a, b in setup),
                                                        snap(A), snap(T), t0)
    print(line, flush=True)
    out.write(line + '\n')
    out.flush()
out.close()
