-- Status screens of every participant, to check the stat model: on
-- Marc's turn, the record of another unit is copied over Marc's record
-- (0x108 bytes) and Status (A, Down x3, A) is opened; the screen then
-- shows that unit's stats. Output: shots/copy_<record>.png.
local OUT = "C:/src/DasBattleCalc/research/"
local STATE = "C:/rom/BizHawk-2.11-win-x64/GBA/State/Final Fantasy Tactics Advance (USA, Australia).mGBA.QuickSave1.State"
local MARC = 0x02000080
local WRAPPERS = 0x020223AC
local function rd32(a) return memory.read_u32_le(a, "System Bus") end

local recs = {}
savestate.load(STATE)
for k = 0, 11 do
  local rec = rd32(WRAPPERS + k * 0x90)
  if rec < 0x02000000 or rec >= 0x02040000 then break end
  recs[#recs + 1] = rec
end

local MACRO = { {90, "A"}, {120, "Down"}, {135, "Down"}, {150, "Down"}, {170, "A"} }
client.speedmode(1600)
for _, src in ipairs(recs) do
  savestate.load(STATE)
  local bytes = {}
  for i = 0, 0x107 do bytes[i] = memory.read_u8(src + i, "System Bus") end
  for t = 0, 270 do
    if t == 60 then
      for i = 0, 0x107 do memory.write_u8(MARC + i, bytes[i], "System Bus") end
    end
    for _, m in ipairs(MACRO) do
      if t == m[1] or t == m[1] + 1 then joypad.set({ [m[2]] = true }) end
    end
    if t == 260 then client.screenshot(string.format("%sshots/copy_%08x.png", OUT, src)) end
    emu.frameadvance()
  end
end
client.exit()
