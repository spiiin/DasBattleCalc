# PPSSPP WebSocket debugger client (ws://127.0.0.1:PORT/debugger).
import json, base64, os, websocket
def _port():
    if os.environ.get('PPSSPP_PORT'): return int(os.environ['PPSSPP_PORT'])
    import psutil
    for p in psutil.process_iter(['name']):
        if (p.info['name'] or '').lower().startswith('ppssppwindows'):
            for c in p.net_connections(kind='tcp'):
                if c.status == psutil.CONN_LISTEN: return c.laddr.port
    raise RuntimeError('PPSSPP with the debugger is not running')
PORT = None
class Dbg:
    def __init__(self, port=None):
        port = port or _port()
        self.ws = websocket.create_connection('ws://127.0.0.1:%d/debugger' % port, timeout=30)
        self.n = 0
    def call(self, event, **kw):
        self.n += 1
        t = 't%d' % self.n
        kw['event'] = event; kw['ticket'] = t
        self.ws.send(json.dumps(kw))
        while True:
            m = json.loads(self.ws.recv())
            if m.get('ticket') == t:
                if m.get('event') == 'error': raise RuntimeError(m.get('message'))
                return m
    def wait(self, event):
        while True:
            m = json.loads(self.ws.recv())
            if m.get('event') == event: return m
    def read(self, addr, size):
        m = self.call('memory.read', address=addr, size=size)
        return base64.b64decode(m['base64'])
    def write(self, addr, data):
        return self.call('memory.write', address=addr, base64=base64.b64encode(data).decode())

def shot(d, path):
    """the PPSSPP window's client area as PNG: PrintWindow, so the window
    may be covered by others (no focus change, no screen grab)"""
    import ctypes, ctypes.wintypes as wt
    from PIL import Image
    u = ctypes.windll.user32; g = ctypes.windll.gdi32
    u.SetProcessDPIAware()
    found = []
    def cb(h, _):
        n = u.GetWindowTextLengthW(h)
        b = ctypes.create_unicode_buffer(n + 1); u.GetWindowTextW(h, b, n + 1)
        if b.value.startswith('PPSSPP') and u.IsWindowVisible(h): found.append(h)
        return True
    u.EnumWindows(ctypes.WINFUNCTYPE(ctypes.c_bool, wt.HWND, wt.LPARAM)(cb), 0)
    h = found[0]
    r = wt.RECT(); u.GetClientRect(h, ctypes.byref(r))
    w, ht = r.right, r.bottom
    hdc = u.GetDC(h); mdc = g.CreateCompatibleDC(hdc); bmp = g.CreateCompatibleBitmap(hdc, w, ht)
    g.SelectObject(mdc, bmp)
    u.PrintWindow(h, mdc, 3)          # PW_CLIENTONLY | PW_RENDERFULLCONTENT
    buf = ctypes.create_string_buffer(w * ht * 4)
    class BIH(ctypes.Structure):
        _fields_ = [('biSize', wt.DWORD), ('biWidth', ctypes.c_long), ('biHeight', ctypes.c_long),
                    ('biPlanes', wt.WORD), ('biBitCount', wt.WORD), ('biCompression', wt.DWORD),
                    ('biSizeImage', wt.DWORD), ('a', ctypes.c_long), ('b', ctypes.c_long),
                    ('c', wt.DWORD), ('e', wt.DWORD)]
    bi = BIH(ctypes.sizeof(BIH), w, -ht, 1, 32, 0, 0, 0, 0, 0, 0)
    g.GetDIBits(mdc, bmp, 0, ht, buf, ctypes.byref(bi), 0)
    g.DeleteObject(bmp); g.DeleteDC(mdc); u.ReleaseDC(h, hdc)
    Image.frombuffer('RGBX', (w, ht), buf, 'raw', 'BGRX', 0, 1).convert('RGB').save(path)

def dump(d, lo=0x08800000, hi=0x09800000, chunk=0x100000):
    """RAM lo..hi as bytes (read in chunks)"""
    out = bytearray()
    for a in range(lo, hi, chunk):
        out += d.read(a, min(chunk, hi - a))
    return bytes(out)

def key(vk, hold=0.15):
    """a key press posted to the PPSSPP window (keyboard mapping of
    controls.ini: W/S/A/D d-pad, H cross, Y circle); no focus change"""
    import ctypes, ctypes.wintypes as wt, time
    u = ctypes.windll.user32
    found = []
    def cb(h, _):
        n = u.GetWindowTextLengthW(h)
        b = ctypes.create_unicode_buffer(n + 1); u.GetWindowTextW(h, b, n + 1)
        if b.value.startswith('PPSSPP') and u.IsWindowVisible(h): found.append(h)
        return True
    u.EnumWindows(ctypes.WINFUNCTYPE(ctypes.c_bool, wt.HWND, wt.LPARAM)(cb), 0)
    h = found[0]
    sc = u.MapVirtualKeyW(vk, 0)
    u.PostMessageW(h, 0x100, vk, 1 | sc << 16)
    time.sleep(hold)
    u.PostMessageW(h, 0x101, vk, 1 | sc << 16 | 0xC0000000)
