-- Fast statistics of one roll: the menus are walked once to the frame
-- before the action is confirmed (PROBE_PLAN, PROBE_SEED_AT), that point
-- is kept as an in-memory core state, and every trial loads it, writes a
-- random seed to 0x030034B0 and runs PROBE_RUN frames. Logged per trial:
-- hit (the hit branch 0x080A28A4 ran), crit (0x080A2978 ran).
local OUT = "C:/src/DasBattleCalc/research/"
local STATE = "C:/rom/BizHawk-2.11-win-x64/GBA/State/Final Fantasy Tactics Advance (USA, Australia).mGBA.QuickSave1.State"
local TRIALS = tonumber(os.getenv("PROBE_TRIALS") or "100")
local SEED_AT = tonumber(os.getenv("PROBE_SEED_AT") or "500")
local RUN = tonumber(os.getenv("PROBE_RUN") or "120")
local PATCHES = os.getenv("PROBE_PATCHES") or ""
local plan = {}
for f, b in string.gmatch(os.getenv("PROBE_PLAN") or "90:A,130:Down,150:A,200:A,300:Left,360:A,430:A,520:A", "(%d+):(%a+)") do
  plan[tonumber(f)] = b
  plan[tonumber(f) + 1] = b
end
local log = io.open(OUT .. (os.getenv("PROBE_LOG") or "roll_probe_log.txt"), "w")
local hit, crit = 0, 0
event.on_bus_exec(function() hit = 1 end, 0x080A28A4)
event.on_bus_exec(function() crit = 1 end, 0x080A2978)
math.randomseed(tonumber(os.getenv("PROBE_RNG") or "1"))
client.speedmode(6400)
savestate.load(STATE)
for f = 0, SEED_AT - 1 do
  local b = plan[f]
  if b then joypad.set({ [b] = true }) end
  if f == 60 then
    for a, s, v in string.gmatch(PATCHES, "(0x%x+):(%d):(%d+)") do
      local addr, size, val = tonumber(a), tonumber(s), tonumber(v)
      if size == 1 then memory.write_u8(addr, val, "System Bus") else memory.write_u16_le(addr, val, "System Bus") end
    end
  end
  emu.frameadvance()
end
local point = memorysavestate.savecorestate()
for t = 1, TRIALS do
  memorysavestate.loadcorestate(point)
  hit, crit = 0, 0
  memory.write_u32_le(0x030034B0, math.random(0, 0xFFFF) * 0x10000 + math.random(0, 0xFFFF), "System Bus")
  for f = SEED_AT, SEED_AT + RUN do
    local b = plan[f]
    if b then joypad.set({ [b] = true }) end
    emu.frameadvance()
  end
  log:write(string.format("%d %d\n", hit, crit))
end
log:close()
client.exit()
