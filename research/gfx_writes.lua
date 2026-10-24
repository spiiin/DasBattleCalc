-- Who writes graphics into VRAM: logs PC, LR and R0-R3 for writes to the
-- chosen bus addresses while an input plan runs (the plan of gfx_probe).
-- PROBE_ADDRS "name:0xADDR,..."; output research/gfx/<tag>_writes.txt.
local OUT = "C:/src/DasBattleCalc/research/"
local speed = dofile(OUT .. "speed.lua")
local STATE = os.getenv("PROBE_STATE") or "C:/rom/BizHawk-2.11-win-x64/GBA/State/ffta_test_battle1.State"
local TAG = os.getenv("PROBE_TAG") or "status"
local PLAN = os.getenv("PROBE_PLAN") or "90:A,120:Down,135:Down,150:Down,170:A"
local FRAMES = tonumber(os.getenv("PROBE_FRAMES") or "260")
local plan = {}
for f, b in string.gmatch(PLAN, "(%d+):(%a+)") do
  plan[tonumber(f)] = b
  plan[tonumber(f) + 1] = b
end
local log = io.open(OUT .. "gfx/" .. TAG .. "_writes.txt", "w")
local frame = 0
local count = {}
local function r(n) return emu.getregister("R" .. n) end
for name, a in string.gmatch(os.getenv("PROBE_ADDRS") or "", "(%w+):(0x%x+)") do
  event.on_bus_write(function(addr, v)
    count[name] = (count[name] or 0) + 1
    if count[name] <= 20 then
      log:write(string.format("%4d %-6s v=%08X pc=%08X lr=%08X r0=%08X r1=%08X r2=%08X r3=%08X\n",
        frame, name, v or 0, r(15), r(14), r(0), r(1), r(2), r(3)))
    end
  end, tonumber(a))
end
savestate.load(STATE)
speed.fast(800)
for f = 0, FRAMES do
  frame = f
  if plan[f] then joypad.set({ [plan[f]] = true }) end
  emu.frameadvance()
end
log:close()
speed.exit()
