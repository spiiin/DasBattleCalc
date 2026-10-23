-- Logs reads of chosen addresses (PC, LR) while running an input plan.
-- PROBE_ADDRS = "name:0xADDR,..."; output research/reads_log.txt.
local OUT = "C:/src/DasBattleCalc/research/"
local speed = dofile(OUT .. "speed.lua")   -- fast, restores the speed on exit
local STATE = "C:/rom/BizHawk-2.11-win-x64/GBA/State/Final Fantasy Tactics Advance (USA, Australia).mGBA.QuickSave1.State"
local FRAMES = tonumber(os.getenv("PROBE_FRAMES") or "600")
local FROM = tonumber(os.getenv("PROBE_FROM") or "0")
local PLAN = os.getenv("PROBE_PLAN") or ""
local ADDRS = os.getenv("PROBE_ADDRS") or ""
local plan = {}
for f, b in string.gmatch(PLAN, "(%d+):(%a+)") do
  plan[tonumber(f)] = b
  plan[tonumber(f) + 1] = b
end
local log = io.open(OUT .. "reads_log.txt", "w")
local frame = 0
for name, a in string.gmatch(ADDRS, "(%w+):(0x%x+)") do
  local addr = tonumber(a)
  local hook = os.getenv("PROBE_MODE") == "write" and event.on_bus_write or event.on_bus_read
  hook(function(ad, v, flags)
    if frame >= FROM then
      log:write(string.format("%5d %-6s pc=%08X lr=%08X\n", frame, name, emu.getregister("R15"), emu.getregister("R14")))
    end
  end, addr)
end
savestate.load(STATE)
speed.fast(800)
for f = 0, FRAMES do
  frame = f
  local b = plan[f]
  if b then joypad.set({ [b] = true }) end
  emu.frameadvance()
end
log:close()
speed.exit()
