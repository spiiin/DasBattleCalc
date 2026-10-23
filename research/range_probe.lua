-- Fight targeting under RAM patches: for each case the state is
-- reloaded, Marc's weapon (record +0x2A) and tile heights are patched,
-- Fight is opened, and every result of the Fight tile rule 0x0809FEF0
-- (at its return 0x080A0002) is logged: case cx cy tx ty result.
-- PROBE_CASES = "name=w:ITEM;h:X,Y,H;...|..."
local OUT = "C:/src/DasBattleCalc/research/"
local STATE = "C:/rom/BizHawk-2.11-win-x64/GBA/State/Final Fantasy Tactics Advance (USA, Australia).mGBA.QuickSave1.State"
local MARC = 0x02000080
local PLAN = { [90] = "A", [130] = "Down", [150] = "A", [200] = "A" }
local log = io.open(OUT .. "range_probe_log.txt", "w")
local name = ""
local active = false
event.on_bus_exec(function()
  if not active then return end
  local sp = emu.getregister("R13")
  local cx = memory.read_u8(sp + 0x0C, "System Bus")
  local cy = memory.read_u8(sp + 0x10, "System Bus")
  local tx = memory.read_u8(sp + 0x14, "System Bus")
  local r10 = emu.getregister("R10")
  local ty = r10 > 255 and (r10 >> 24) & 0xff or r10
  log:write(string.format("%s %d %d %d %d %d\n", name, cx, cy, tx, ty, emu.getregister("R0")))
end, 0x080A0002)
client.speedmode(1600)
for case in string.gmatch(os.getenv("PROBE_CASES") or "base=", "[^|]+") do
  local n, patches = string.match(case, "([^=]*)=(.*)")
  name = n
  savestate.load(STATE)
  local tiles = memory.read_u32_le(0x02007F14, "System Bus")
  local stride = memory.read_u8(0x02007F18, "System Bus")
  for f = 0, 320 do
    local b = PLAN[f] or PLAN[f - 1]
    if b then joypad.set({ [b] = true }) end
    if f == 60 then
      for w in string.gmatch(patches, "w:(%d+)") do memory.write_u16_le(MARC + 0x2A, tonumber(w), "System Bus") end
      for x, y, h in string.gmatch(patches, "h:(%d+),(%d+),(%d+)") do
        memory.write_u8(tiles + (tonumber(y) * stride + tonumber(x)) * 2, tonumber(h), "System Bus")
      end
    end
    active = f >= 195
    emu.frameadvance()
  end
  client.screenshot(string.format("%sshots/range_%s.png", OUT, n))
end
log:close()
client.exit()
