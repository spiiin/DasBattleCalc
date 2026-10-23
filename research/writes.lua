-- Logs every write to the CT (+0xD0) and reserve (+0xD4) fields of the
-- battle units, with the program counter, while running an input plan.
local OUT = "C:/src/DasBattleCalc/research/"
local speed = dofile(OUT .. "speed.lua")   -- fast, restores the speed on exit
local STATE = os.getenv("PROBE_STATE") or "C:/rom/BizHawk-2.11-win-x64/GBA/State/ffta_test_battle1.State"
local FRAMES = tonumber(os.getenv("PROBE_FRAMES") or "1200")
local PLAN = os.getenv("PROBE_PLAN") or ""

local UNITS = {
  {"Marc", 0x02000080}, {"Lunais", 0x02002fc4}, {"Euver", 0x020030cc},
  {"Montblanc", 0x020031d4}, {"Judge", 0x020032dc},
}
local plan = {}
for f, b in string.gmatch(PLAN, "(%d+):(%a+)") do
  plan[tonumber(f)] = b
  plan[tonumber(f) + 1] = b
end

local log = io.open(OUT .. "writes_log.txt", "w")
local frame = 0
for _, u in ipairs(UNITS) do
  for _, f in ipairs({ {0xD0, "ct"}, {0xD4, "rs"} }) do
    local addr = u[2] + f[1]
    event.on_bus_write(function(a, v, flags)
      log:write(string.format("%6d %-9s %s pc=%08X lr=%08X val=%d\n", frame, u[1], f[2],
        emu.getregister("R15"), emu.getregister("R14"), v or -1))
    end, addr)
  end
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
