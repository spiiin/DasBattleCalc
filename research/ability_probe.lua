-- Battle Tech of Marc -> Montblanc under RAM patches. For each case:
-- reload, write the patches, open Action > Battle Tech, take the k-th
-- ability ("pick:k"), target Montblanc; log the preview (damage: the
-- result of 0x0812FE38 at 0x081300F2, r5; hit chance: 0x0812C8C6, r0;
-- effect value: 0x080B5730, r0), then use it and log what changed in
-- both unit records (CT bytes +0xD0..+0xD5 left out).
-- PROBE_CASES = "name=pick:K;addr:size:val;...|..."
local OUT = "C:/src/DasBattleCalc/research/"
local speed = dofile(OUT .. "speed.lua")   -- fast, restores the speed on exit
local STATE = "C:/rom/BizHawk-2.11-win-x64/GBA/State/Final Fantasy Tactics Advance (USA, Australia).mGBA.QuickSave1.State"
local FRAMES = tonumber(os.getenv("PROBE_FRAMES") or "1100")
local UNITS = { 0x02000080, 0x020031D4, 0x020030CC }
local log = io.open(OUT .. "ability_probe_log.txt", "w")
local vals = {}
local function put(k, v) vals[#vals + 1] = k .. "=" .. tostring(v) end
event.on_bus_exec(function() put("dmg", emu.getregister("R5")) end, 0x081300F2)
event.on_bus_exec(function() put("hit", emu.getregister("R0")) end, 0x0812C8C6)
event.on_bus_exec(function() put("eff", emu.getregister("R0")) end, 0x080B5730)
event.on_bus_exec(function() put("A", emu.getregister("R0")) end, 0x0812FE86)
event.on_bus_exec(function() put("D", emu.getregister("R0")) end, 0x0812FEA0)
-- PROBE_DUMP=1: the whole EWRAM before / after the use
local function dump_ewram(file)
  local bytes = memory.read_bytes_as_array(0, 0x40000, "EWRAM")
  local parts = {}
  for i = 1, #bytes do parts[i] = string.char(bytes[i]) end
  local f = io.open(OUT .. file, "wb")
  f:write(table.concat(parts))
  f:close()
end
speed.fast(1600)
for case in string.gmatch(os.getenv("PROBE_CASES") or "base=", "[^|]+") do
  local name, patches = string.match(case, "([^=]*)=(.*)")
  local pick = tonumber(string.match(patches, "pick:(%d+)") or "0")
  local plan = { [90] = "A", [130] = "Down", [150] = "A", [190] = "Down", [210] = "A" }
  for k = 1, pick do plan[240 + k * 15] = "Down" end
  plan[360] = "A"
  plan[400] = string.match(patches, "dir:(%a+)") or "Left"
  plan[440] = "A"
  plan[480] = "A"
  plan[580] = "A"
  plan[660] = "A"
  savestate.load(STATE)
  vals = {}
  local before = {}
  for f = 0, FRAMES do
    local b = plan[f] or plan[f - 1]
    if b then joypad.set({ [b] = true }) end
    if f == 60 then
      for src, dst in string.gmatch(patches, "copy(0x%x+)>(0x%x+)") do
        local from, to = tonumber(src), tonumber(dst)
        for i = 0, 0x107 do memory.write_u8(to + i, memory.read_u8(from + i, "System Bus"), "System Bus") end
      end
      for a, s, v in string.gmatch(patches, "(0x%x+):(%d):(%d+)") do
        local addr, size, val = tonumber(a), tonumber(s), tonumber(v)
        if size == 1 then memory.write_u8(addr, val, "System Bus") else memory.write_u16_le(addr, val, "System Bus") end
      end
    end
    if f == 395 then vals = {} end
    if f == 470 then
      client.screenshot(string.format("%sshots/ab_%s.png", OUT, name))
      log:write(name .. " preview " .. table.concat(vals, " ") .. "\n")
      vals = {}
      for _, r in ipairs(UNITS) do before[r] = memory.read_bytes_as_array(r, 0x108, "System Bus") end
      if os.getenv("PROBE_DUMP") then dump_ewram("ab_before.bin") end
    end
    if os.getenv("PROBE_SHOTS") and f % 30 == 0 and f >= 420 then
      client.screenshot(string.format("%sshots/f%05d.png", OUT, f))
    end
    emu.frameadvance()
  end
  log:write("  use " .. table.concat(vals, " ") .. "\n")
  if os.getenv("PROBE_DUMP") then dump_ewram("ab_after.bin") end
  for _, r in ipairs(UNITS) do
    local after = memory.read_bytes_as_array(r, 0x108, "System Bus")
    local d = {}
    for i = 1, 0x108 do
      if before[r][i] ~= after[i] and (i - 1 < 0xD0 or i - 1 > 0xD5) then
        d[#d + 1] = string.format("+%02X:%d>%d", i - 1, before[r][i], after[i])
      end
    end
    log:write(string.format("  %08x %s\n", r, table.concat(d, " ")))
  end
  client.screenshot(string.format("%sshots/ab_%s_after.png", OUT, name))
end
log:close()
speed.exit()
