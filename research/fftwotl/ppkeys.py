# Real keyboard input to PPSSPP (SendInput, scan codes) - the game's
# target cursor ignores the debugger's input. controls.ini: W/A/S/D d-pad,
# H cross, Y circle, 2 select; PPSSPP hotkeys F2 save state, F3 next slot.
#   python ppkeys.py H S D ...      (each argument: a key, or sleep:SEC, shot:NAME)
import ctypes, ctypes.wintypes as wt, sys, time
u = ctypes.windll.user32
SC = {'W': 0x11, 'A': 0x1E, 'S': 0x1F, 'D': 0x20, 'H': 0x23, 'Y': 0x15, '2': 0x03, 'F2': 0x3C, 'F3': 0x3D, 'F4': 0x3E}
class KI(ctypes.Structure):
    _fields_ = [('wVk', wt.WORD), ('wScan', wt.WORD), ('dwFlags', wt.DWORD), ('time', wt.DWORD), ('extra', ctypes.c_size_t)]
class INP(ctypes.Structure):
    class _U(ctypes.Union):
        _fields_ = [('ki', KI), ('pad', ctypes.c_byte * 32)]
    _anonymous_ = ('u',)
    _fields_ = [('type', wt.DWORD), ('u', _U)]
def window():
    found = []
    def cb(h, _):
        n = u.GetWindowTextLengthW(h)
        b = ctypes.create_unicode_buffer(n + 1); u.GetWindowTextW(h, b, n + 1)
        if b.value.startswith('PPSSPP') and u.IsWindowVisible(h): found.append(h)
        return True
    u.EnumWindows(ctypes.WINFUNCTYPE(ctypes.c_bool, wt.HWND, wt.LPARAM)(cb), 0)
    return found[0]
def send(sc, up):
    i = INP(type=1); i.ki = KI(0, sc, 0x0008 | (0x0002 if up else 0), 0, 0)
    u.SendInput(1, ctypes.byref(i), ctypes.sizeof(INP))
def tap(name, hold=0.12, after=0.6):
    send(SC[name], False); time.sleep(hold); send(SC[name], True); time.sleep(after)
def run(args):
    prev = u.GetForegroundWindow()
    h = window()
    u.ShowWindow(h, 9); u.SetForegroundWindow(h); time.sleep(0.4)
    try:
        for a in args:
            if a.startswith('sleep:'): time.sleep(float(a[6:]))
            elif a.startswith('shot:'):
                from ppdbg import Dbg, shot
                shot(None, 'shots/' + a[5:] + '.png')
            else: tap(a)
    finally:
        if prev: u.SetForegroundWindow(prev)
if __name__ == '__main__':
    run(sys.argv[1:])
