# Start PPSSPP with the ISO and a save state, wait for its debugger port.
#   python pprun.py state.ppst   -> prints the port (also used by ppdbg via PPSSPP_PORT)
import os, subprocess, sys, time, psutil
EXE = r'c:\rom\psx\PPSSPP\PPSSPPWindows64.exe'
ISO = r'c:\rom\psx\rom\Final_Fantasy_Tactics_The_War_Of_The_Lions_USA_PSP-pSyPSP.iso'
def kill_all():
    for p in psutil.process_iter(['name']):
        if (p.info['name'] or '').lower().startswith('ppssppwindows'):
            p.kill(); p.wait(10)
def start(state, settle=6.0):
    kill_all()
    p = subprocess.Popen([EXE, '--state=' + os.path.abspath(state), ISO])
    proc = psutil.Process(p.pid)
    for _ in range(100):
        ports = [c.laddr.port for c in proc.net_connections(kind='tcp') if c.status == psutil.CONN_LISTEN]
        if ports: break
        time.sleep(0.2)
    time.sleep(settle)
    os.environ['PPSSPP_PORT'] = str(ports[0])
    return ports[0]
if __name__ == '__main__':
    print(start(sys.argv[1]))
