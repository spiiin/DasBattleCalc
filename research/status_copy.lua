-- Status screens of every participant, to check the stat model: on
-- Marc's turn, the record of another unit is copied over Marc's record
-- (0x108 bytes) and Status (A, Down x3, A) is opened; the screen then
-- shows that unit's stats. Output: shots/copy_<record>.png.
local OUT = "C:/src/DasBattleCalc/research/"
local speed = dofile(OUT .. "speed.lua")   -- fast, restores the speed on exit
local STATE = os.getenv("PROBE_STATE") or "C:/rom/BizHawk-2.11-win-x64/GBA/State/ffta_test_battle1.State"
-- the unit whose turn it is (Marc in the first battle, Loki 0x02000398 in the second)
local MARC = tonumber(os.getenv("PROBE_ACTOR") or "0x02000080")
local WRAPPERS = 0x020223AC
local function rd32(a) return memory.read_u32_le(a, "System Bus") end

local recs = {}
savestate.load(STATE)
for k = 0, 11 do
  local rec = rd32(WRAPPERS + k * 0x90)
  if rec < 0x02000000 or rec >= 0x02040000 then break end
  recs[#recs + 1] = rec
end

-- frames of the menu presses; PROBE_DELAY shifts them (the camera of the
-- second battle needs longer before the menu takes input)
local D = tonumber(os.getenv("PROBE_DELAY") or "0")
local MACRO = { {90 + D, "A"}, {120 + D, "Down"}, {135 + D, "Down"}, {150 + D, "Down"}, {170 + D, "A"} }
-- PROBE_MACRO "frame:Button,...": other presses (the second battle's save
-- is already in the menu: Down x3, A); PROBE_COPY_AT: when to copy
if os.getenv("PROBE_MACRO") then
  MACRO = {}
  for f, b in string.gmatch(os.getenv("PROBE_MACRO"), "(%d+):(%a+)") do MACRO[#MACRO + 1] = { tonumber(f), b } end
end
local COPY_AT = tonumber(os.getenv("PROBE_COPY_AT") or "60")
speed.fast(1600)
for _, src in ipairs(recs) do
  savestate.load(STATE)
  local bytes = {}
  for i = 0, 0x107 do bytes[i] = memory.read_u8(src + i, "System Bus") end
  local flags = memory.read_u16_le(MARC + 0x28, "System Bus")
  for t = 0, 270 + D do
    if t == COPY_AT then
      for i = 0, 0x107 do memory.write_u8(MARC + i, bytes[i], "System Bus") end
      -- keep the actor's flags: an enemy's (0x8000) would hand the turn to the AI
      memory.write_u16_le(MARC + 0x28, flags, "System Bus")
    end
    for _, m in ipairs(MACRO) do
      if t == m[1] or t == m[1] + 1 then joypad.set({ [m[2]] = true }) end
    end
    if t == 260 + D then client.screenshot(string.format("%sshots/copy_%08x.png", OUT, src)) end
    emu.frameadvance()
  end
end
speed.exit()
