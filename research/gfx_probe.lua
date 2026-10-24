-- Where the game's graphics come from: logs every call of the game's
-- decompressors (0x0801F100 picks the format by the first byte;
-- 0x08005318, 0x0800543C) and VRAM copies (0x0814186C) while an input
-- plan runs, and dumps VRAM, palette RAM and OAM with a screenshot at
-- chosen frames.
-- PROBE_PLAN "frame:Button,..." (default: Status of the unit whose turn
-- it is), PROBE_DUMPS "frame,frame" (default 30,260), PROBE_TAG names the
-- outputs: research/gfx/<tag>_log.txt, <tag>_<frame>_{vram,pal,oam}.bin,
-- <tag>_<frame>.png.
local OUT = "C:/src/DasBattleCalc/research/"
local speed = dofile(OUT .. "speed.lua")   -- fast, restores the speed on exit
local STATE = os.getenv("PROBE_STATE") or "C:/rom/BizHawk-2.11-win-x64/GBA/State/ffta_test_battle1.State"
local TAG = os.getenv("PROBE_TAG") or "status"
local PLAN = os.getenv("PROBE_PLAN") or "90:A,120:Down,135:Down,150:Down,170:A"
local DUMPS = os.getenv("PROBE_DUMPS") or "30,260"
local DIR = OUT .. "gfx/"
os.execute('mkdir "' .. DIR:gsub("/", "\\") .. '" 2>nul')

local plan, dumps, last = {}, {}, 0
for f, b in string.gmatch(PLAN, "(%d+):(%a+)") do
  plan[tonumber(f)] = b
  plan[tonumber(f) + 1] = b
end
for f in string.gmatch(DUMPS, "%d+") do
  dumps[tonumber(f)] = true
  last = math.max(last, tonumber(f))
end

local log = io.open(DIR .. TAG .. "_log.txt", "w")
local frame = 0
local function r(n) return emu.getregister("R" .. n) end
local function hook(name, addr)
  event.on_bus_exec(function()
    local src = r(0)
    local head = 0
    if src >= 0x08000000 and src < 0x0A000000 then head = memory.read_u32_le(src, "System Bus") end
    log:write(string.format("%4d %-5s src=%08X dst=%08X r2=%08X r3=%08X lr=%08X head=%08X\n",
      frame, name, src, r(1), r(2), r(3), r(14), head))
  end, addr)
end
hook("dec", 0x0801F100)
hook("d5318", 0x08005318)   -- (src, dst, ?, ?): src in r0
-- (dst, src): src in r1
event.on_bus_exec(function()
  local src = r(1)
  local head = 0
  if src >= 0x08000000 and src < 0x0A000000 then head = memory.read_u32_le(src, "System Bus") end
  log:write(string.format("%4d d543C src=%08X dst=%08X lr=%08X head=%08X\n", frame, src, r(0), r(14), head))
end, 0x0800543C)
-- CpuSet / CpuFastSet wrapper: VRAM copies (src r0, dst r1, count r2)
event.on_bus_exec(function()
  if r(1) >= 0x06000000 and r(1) < 0x07000000 then
    log:write(string.format("%4d copy  src=%08X dst=%08X n=%08X lr=%08X\n", frame, r(0), r(1), r(2), r(14)))
  end
end, 0x0814186C)

local function dump(domain, size, path)
  local f = io.open(path, "wb")
  local bytes = memory.read_bytes_as_array(0, size, domain)
  local parts = {}
  for i = 1, #bytes do parts[#parts + 1] = string.char(bytes[i]) end
  f:write(table.concat(parts))
  f:close()
end

savestate.load(STATE)
speed.fast(800)
for f = 0, last do
  frame = f
  if plan[f] then joypad.set({ [plan[f]] = true }) end
  if dumps[f] then
    local p = string.format("%s%s_%03d", DIR, TAG, f)
    dump("VRAM", 0x18000, p .. "_vram.bin")
    dump("PALRAM", 0x400, p .. "_pal.bin")
    dump("OAM", 0x400, p .. "_oam.bin")
    dump("EWRAM", 0x40000, p .. "_ewram.bin")
    client.screenshot(p .. ".png")
    log:write(string.format("%4d dump %s\n", f, p))
  end
  emu.frameadvance()
end
log:close()
speed.exit()
