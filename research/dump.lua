-- Runs an input plan and dumps EWRAM / IWRAM at the given frames:
-- PROBE_DUMPS = "300,420" -> dump_300_ewram.bin, dump_300_iwram.bin ...
local OUT = "C:/src/DasBattleCalc/research/"
local speed = dofile(OUT .. "speed.lua")   -- fast, restores the speed on exit
local STATE = os.getenv("PROBE_STATE") or "C:/rom/BizHawk-2.11-win-x64/GBA/State/ffta_test_battle1.State"
local PLAN = os.getenv("PROBE_PLAN") or ""
local plan, dumps, last = {}, {}, 0
for f, b in string.gmatch(PLAN, "(%d+):(%a+)") do
  plan[tonumber(f)] = b
  plan[tonumber(f) + 1] = b
end
for f in string.gmatch(os.getenv("PROBE_DUMPS") or "", "(%d+)") do
  dumps[tonumber(f)] = true
  last = math.max(last, tonumber(f))
end
local function dump(name, domain, size, f)
  local file = io.open(string.format("%sdump_%d_%s.bin", OUT, f, name), "wb")
  local bytes = memory.read_bytes_as_array(0, size, domain)
  local parts = {}
  for i = 1, size do parts[i] = string.char(bytes[i]) end
  file:write(table.concat(parts))
  file:close()
end
savestate.load(STATE)
speed.fast(800)
for f = 0, last do
  local b = plan[f]
  if b then joypad.set({ [b] = true }) end
  if dumps[f] then
    dump("ewram", "EWRAM", 0x40000, f)
    dump("iwram", "IWRAM", 0x8000, f)
    client.screenshot(string.format("%sshots/dump_%d.png", OUT, f))
  end
  emu.frameadvance()
end
speed.exit()
