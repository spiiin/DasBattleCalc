# Forecast probe: with the target confirmed (the forecast on screen), edit
# RAM, cancel (circle) and confirm (cross) again, read the game's forecast
# from the target record: +0x1B6 HP damage (u16), +0x1DC hit %.
import struct, time
from ppdbg import Dbg
import ppkeys
REC, SZ = 0x092E5CB4, 0x1E8
d = Dbg()
def rec(k): return REC + k * SZ
def w8(a, v): d.write(a, bytes([v & 255]))
def w16(a, v): d.write(a, struct.pack('<H', v & 0xFFFF))
def r8(a): return d.read(a, 1)[0]
import pprun
STATE = 'C:/rom/psx/PPSSPP/memstick/PSP/PPSSPP_STATE/fftwotl_test_battle1.ppst'
# Keys go through the debugger (input.buttons.press): no window focus, so
# nothing reaches other windows. Letters as in controls.ini: W/A/S/D the
# d-pad, H cross, Y circle. From the state: menu, Act, Attack (the help
# box), close it, the cursor to Lezalas (up-right of Ramza), confirm.
FRESH = ['Y', 'S', 'H', 'H', 'sleep:0.6', 'H', 'sleep:0.5', 'W', 'sleep:0.5', 'H', 'sleep:1.0']
BUTTONS = {'W': 'up', 'S': 'down', 'A': 'left', 'D': 'right', 'H': 'cross', 'Y': 'circle'}
def focus():
    pass                                # the debugger's input needs no focus
def keys(seq):
    for a in seq:
        if a.startswith('sleep:'): time.sleep(float(a[6:]))
        else:
            d.call('input.buttons.press', button=BUTTONS[a], duration=6)
            time.sleep(0.7)
SETUP = []        # (address, bytes) written after a restart, before the keys
def restart():
    global d
    pprun.start(STATE, settle=7)
    d = Dbg()
    for a, b in SETUP:
        d.write(a, b)
    focus()
    keys(FRESH)
def forecast(tgt, retrigger=True):
    """the game's forecast on the target (dmg, hit, kind); None when the
    forecast did not come"""
    d.write(rec(tgt) + 0x1DC, bytes([0xEE]))
    if retrigger:
        keys(['Y', 'sleep:0.9', 'H', 'sleep:1.4'])
    b = d.read(rec(tgt), SZ)
    if b[0x1DC] == 0xEE:
        return None
    return struct.unpack_from('<H', b, 0x1B6)[0], b[0x1DC], b[0x1CA]
