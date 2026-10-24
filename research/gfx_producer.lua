-- Who queues the unit sprite frames: the DMA scheduler (0x08000822)
-- reads an entry r4 (+0x08 source, +0x0C destination). Step 1 logs the
-- entries that copy into OBJ VRAM; with PROBE_ENTRY set, step 2 logs the
-- writes of that entry's source word (+4) (PC, LR, R0-R7).
-- Output: research/gfx/producer_log.txt.
local OUT = "C:/src/DasBattleCalc/research/"
local speed = dofile(OUT .. "speed.lua")
local STATE = os.getenv("PROBE_STATE") or "C:/rom/BizHawk-2.11-win-x64/GBA/State/ffta_test_battle1.State"
local FRAMES = tonumber(os.getenv("PROBE_FRAMES") or "40")
local ENTRY = tonumber(os.getenv("PROBE_ENTRY") or "0")
local log = io.open(OUT .. "gfx/producer_log.txt", "w")
local frame = 0
local function r(n) return emu.getregister("R" .. n) end
local function rd32(a) return memory.read_u32_le(a, "System Bus") end
event.on_bus_exec(function()
  local e = r(4)
  local dst = rd32(e + 8)
  if dst >= 0x06010000 and dst < 0x06018000 then
    log:write(string.format("%3d entry=%08X r1=%08X r5=%08X +04=%08X +08=%08X +0C=%08X +10=%08X\n",
      frame, e, r(1), r(5), rd32(e + 4), dst, rd32(e + 0x0C), rd32(e + 0x10)))
  end
end, 0x08000820)
-- the frame producer: src = offset (r0 after 0x08021044) + sheet base (obj +0x20)
event.on_bus_exec(function()
  local o = r(5)
  log:write(string.format("%3d obj=%08X frame_off=%08X base=%08X size=%04X tile=%04X\n",
    frame, o, r(0), rd32(o + 0x20), memory.read_u16_le(o + 0x24, "System Bus"),
    memory.read_u16_le(o + 0x12, "System Bus")))
end, 0x08021200)
if ENTRY ~= 0 then
  event.on_bus_write(function(addr, v)
    log:write(string.format("%3d write %08X v=%08X pc=%08X lr=%08X r0=%08X r1=%08X r2=%08X r3=%08X r4=%08X r5=%08X r6=%08X r7=%08X\n",
      frame, addr, v or 0, r(15), r(14), r(0), r(1), r(2), r(3), r(4), r(5), r(6), r(7)))
  end, ENTRY + 4)
end
savestate.load(STATE)
speed.fast(800)
for f = 0, FRAMES do
  frame = f
  emu.frameadvance()
end
log:close()
speed.exit()
