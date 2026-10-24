-- The portrait and palette numbers the game picks for every participant:
-- as in status_copy.lua, on Marc's turn the record of another unit is
-- copied over Marc's record (0x108 bytes, Marc's flags kept) and Status
-- (A, Down x3, A) is opened; the lookups of the portrait table
-- (0x080071A8 with 0x083E105C) and the palette loader (0x080CB8D4) are
-- logged. Output: gfx/portrait_ids.txt.
local OUT = "C:/src/DasBattleCalc/research/"
local speed = dofile(OUT .. "speed.lua")   -- fast, restores the speed on exit
local STATE = os.getenv("PROBE_STATE") or "C:/rom/BizHawk-2.11-win-x64/GBA/State/ffta_test_battle1.State"
local MARC = tonumber(os.getenv("PROBE_ACTOR") or "0x02000080")
local WRAPPERS = 0x020223AC
local function rd32(a) return memory.read_u32_le(a, "System Bus") end
local function r(n) return emu.getregister("R" .. n) end

local log = io.open(OUT .. "gfx/portrait_ids.txt", "w")
local cur = 0
event.on_bus_exec(function()
  if r(0) == 0x083E105C then log:write(string.format("%08X portrait %d\n", cur, r(1))) end
end, 0x080071A8)
event.on_bus_exec(function()
  log:write(string.format("%08X palette %d\n", cur, r(1)))
end, 0x080CB8D4)

local recs = {}
savestate.load(STATE)
for k = 0, 11 do
  local rec = rd32(WRAPPERS + k * 0x90)
  if rec < 0x02000000 or rec >= 0x02040000 then break end
  recs[#recs + 1] = rec
end

local D = tonumber(os.getenv("PROBE_DELAY") or "0")
local MACRO = { {90 + D, "A"}, {120 + D, "Down"}, {135 + D, "Down"}, {150 + D, "Down"}, {170 + D, "A"} }
if os.getenv("PROBE_MACRO") then
  MACRO = {}
  for f, b in string.gmatch(os.getenv("PROBE_MACRO"), "(%d+):(%a+)") do MACRO[#MACRO + 1] = { tonumber(f), b } end
end
local COPY_AT = tonumber(os.getenv("PROBE_COPY_AT") or "60")
speed.fast(1600)
for _, src in ipairs(recs) do
  savestate.load(STATE)
  cur = src
  local bytes = {}
  for i = 0, 0x107 do bytes[i] = memory.read_u8(src + i, "System Bus") end
  local flags = memory.read_u16_le(MARC + 0x28, "System Bus")
  for t = 0, 270 + D do
    if t == COPY_AT then
      for i = 0, 0x107 do memory.write_u8(MARC + i, bytes[i], "System Bus") end
      memory.write_u16_le(MARC + 0x28, flags, "System Bus")
    end
    for _, m in ipairs(MACRO) do
      if t == m[1] or t == m[1] + 1 then joypad.set({ [m[2]] = true }) end
    end
    if t == 265 + D then client.screenshot(string.format("%sgfx/ids_%08x.png", OUT, src)) end
    emu.frameadvance()
  end
end
log:close()
speed.exit()
