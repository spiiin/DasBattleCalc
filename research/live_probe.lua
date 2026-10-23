-- Real hits for statistics: for each trial the state is reloaded, the
-- patches written, the action chosen, and right before it is confirmed
-- the game's random seed (0x030034B0, LCG x * 0x41C64E6D + 0x3039) is set
-- to a different value. Logged per trial: the target's HP and MP change,
-- whether the critical hit path ran (0x080A2978), the hit chance the roll
-- used (0x080A2872 r5) and whether the target was pushed back.
-- PROBE_TRIALS, PROBE_PLAN ("frame:Button,..."), PROBE_PATCHES
-- ("addr:size:val;..."), PROBE_TARGET (record), PROBE_WRAPPER (target's).
local OUT = "C:/src/DasBattleCalc/research/"
local STATE = "C:/rom/BizHawk-2.11-win-x64/GBA/State/Final Fantasy Tactics Advance (USA, Australia).mGBA.QuickSave1.State"
local TRIALS = tonumber(os.getenv("PROBE_TRIALS") or "20")
local SEED_AT = tonumber(os.getenv("PROBE_SEED_AT") or "500")
local END_AT = tonumber(os.getenv("PROBE_END") or "820")
local TARGET = tonumber(os.getenv("PROBE_TARGET") or "0x020031D4")
local WRAPPER = tonumber(os.getenv("PROBE_WRAPPER") or "0x020224CC")
local PATCHES = os.getenv("PROBE_PATCHES") or ""
local OTHER = tonumber(os.getenv("PROBE_OTHER") or "0x02000080")   -- the attacker: HP lost to a reaction
local plan = {}
for f, b in string.gmatch(os.getenv("PROBE_PLAN") or "90:A,130:Down,150:A,200:A,300:Left,360:A,430:A,520:A", "(%d+):(%a+)") do
  plan[tonumber(f)] = b
  plan[tonumber(f) + 1] = b
end
local log = io.open(OUT .. (os.getenv("PROBE_LOG") or "live_probe_log.txt"), "w")
local crit, roll = 0, -1
event.on_bus_exec(function() crit = 1 end, 0x080A2978)
event.on_bus_exec(function() roll = emu.getregister("R5") end, 0x080A2872)
local trace = {}
if os.getenv("PROBE_TRACE") then
  event.on_bus_exec(function() trace[#trace + 1] = "pre=" .. emu.getregister("R5") end, 0x08130072)
  event.on_bus_exec(function() trace[#trace + 1] = "k=" .. emu.getregister("R4") end, 0x08130088)
  event.on_bus_exec(function() trace[#trace + 1] = "mod=" .. emu.getregister("R0") end, 0x08130094)
  event.on_bus_exec(function() trace[#trace + 1] = "out=" .. emu.getregister("R5") end, 0x0813009C)
  event.on_bus_exec(function() trace[#trace + 1] = "A=" .. emu.getregister("R0") end, 0x0812FE86)
  event.on_bus_exec(function() trace[#trace + 1] = "D=" .. emu.getregister("R0") end, 0x0812FEA0)
  event.on_bus_exec(function() trace[#trace + 1] = "CRIT" end, 0x080A2978)
  event.on_bus_exec(function()
    trace[#trace + 1] = string.format("ROLL(p=%d,seed=%08x,lr=%08x)", emu.getregister("R0"),
      memory.read_u32_le(0x030034B0, "System Bus"), emu.getregister("R14"))
  end, 0x0812F1DC)
  event.on_bus_exec(function() trace[#trace + 1] = "=>" .. emu.getregister("R0") end, 0x0812F22A)
  event.on_bus_exec(function() trace[#trace + 1] = "critp=" .. emu.getregister("R0") end, 0x080A28FC)
end
local function rd16(a) return memory.read_u16_le(a, "System Bus") end
math.randomseed(tonumber(os.getenv("PROBE_RNG") or "1"))
client.speedmode(6400)
for t = 1, TRIALS do
  savestate.load(STATE)
  crit, roll = 0, -1
  trace = {}
  local hp, mp, x, y, st, ohp
  for f = 0, END_AT do
    local b = plan[f]
    if b then joypad.set({ [b] = true }) end
    if f == 60 then
      for src, dst in string.gmatch(PATCHES, "copy(0x%x+)>(0x%x+)") do
        for i = 0, 0x107 do
          memory.write_u8(tonumber(dst) + i, memory.read_u8(tonumber(src) + i, "System Bus"), "System Bus")
        end
      end
      for a, s, v in string.gmatch(PATCHES, "(0x%x+):(%d):(%d+)") do
        local addr, size, val = tonumber(a), tonumber(s), tonumber(v)
        if size == 1 then memory.write_u8(addr, val, "System Bus") else memory.write_u16_le(addr, val, "System Bus") end
      end
    end
    if f == SEED_AT then
      -- a random 32-bit seed: seeds in a line (t * K) give correlated
      -- rolls through the game's LCG (a residue of rand % 5 never came)
      memory.write_u32_le(0x030034B0, math.random(0, 0xFFFF) * 0x10000 + math.random(0, 0xFFFF), "System Bus")
      hp, mp = rd16(TARGET + 0x18), rd16(TARGET + 0x1C)
      ohp = rd16(OTHER + 0x18)
      st = memory.read_bytes_as_array(TARGET + 0xE8, 6, "System Bus")
      x, y = rd16(WRAPPER + 0x08), rd16(WRAPPER + 0x0C)
    end
    emu.frameadvance()
  end
  local moved = (rd16(WRAPPER + 0x08) ~= x or rd16(WRAPPER + 0x0C) ~= y) and 1 or 0
  local after = memory.read_bytes_as_array(TARGET + 0xE8, 6, "System Bus")
  local sd = {}
  for i = 1, 6 do
    if after[i] ~= st[i] then sd[#sd + 1] = string.format("%02X:%02X>%02X", 0xE7 + i, st[i], after[i]) end
  end
  log:write(string.format("%d hp %d mp %d crit %d roll %d pushed %d status %s other %d\n", t, hp - rd16(TARGET + 0x18),
    mp - rd16(TARGET + 0x1C), crit, roll, moved, #sd > 0 and table.concat(sd, ",") or "-", ohp - rd16(OTHER + 0x18)))
  if #trace > 0 then log:write("  " .. table.concat(trace, " ") .. "\n") end
end
log:close()
client.exit()
