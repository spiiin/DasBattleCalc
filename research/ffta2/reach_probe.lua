-- The tiles the game highlights as in reach, for edited heights and
-- abilities: from the state at the target cursor (Luso next to Sasarr,
-- ffta2_test_attack.State) per case: write the edits, go back (B) and
-- choose the target again (A); the reach builder 0x02045F50 (r3 = the
-- ability) fills a list of (x, y) bytes at its r0; its count is the
-- return value (at 0x020725B4, the second call).
--   case line: name [ab=<id>] [h=x,y,height ...] [addr:size:value ...]
-- Output: reach_log.txt, "name count x,y x,y ...".
local OUT = "C:/src/DasBattleCalc/research/ffta2/"
local speed = dofile("C:/src/DasBattleCalc/research/speed.lua")
local STATE = os.getenv("PROBE_STATE") or "C:/rom/BizHawk-2.11-win-x64/NDS/State/ffta2_test_attack.State"
local CASES = os.getenv("PROBE_CASES") or (OUT .. "reach_cases.txt")
local SETTLE = tonumber(os.getenv("PROBE_SETTLE") or "70")

local function rd(a, n)
  a = a - 0x02000000
  if n == 1 then return memory.read_u8(a, "Main RAM") end
  if n == 2 then return memory.read_u16_le(a, "Main RAM") end
  return memory.read_u32_le(a, "Main RAM")
end
local function wr(a, n, v)
  a = a - 0x02000000
  if n == 1 then memory.write_u8(a, v, "Main RAM")
  elseif n == 2 then memory.write_u16_le(a, v, "Main RAM")
  else memory.write_u32_le(a, v, "Main RAM") end
end
local function frames(n, keys)
  for _ = 1, n do
    if keys then joypad.set(keys) end
    emu.frameadvance()
  end
end

local ability = 0
local buffer = 0
local result = nil
event.on_bus_exec(function()
  if ability ~= 0 then emu.setregister("ARM9 r3", ability) end
  buffer = emu.getregister("ARM9 r0")
end, 0x02045F50)
event.on_bus_exec(function()
  if buffer ~= 0 then
    local n = emu.getregister("ARM9 r0")
    local tiles = {}
    for i = 0, n - 1 do
      tiles[#tiles + 1] = string.format("%d,%d", rd(buffer + 2 * i, 1), rd(buffer + 2 * i + 1, 1))
    end
    result = string.format("%d %s", n, table.concat(tiles, " "))
  end
end, 0x020725B4)

local log = io.open(OUT .. "reach_log.txt", "w")
savestate.load(STATE)
speed.fast(1600)
frames(5)
local panl = rd(rd(0x0212EEA8, 4) + 0xF4, 4)
local w = rd(panl + 8, 1)
log:write(string.format("# PANL %08X w %d\n", panl, w))
for line in io.lines(CASES) do
  local name, rest = string.match(line, "^(%S+)%s*(.*)$")
  if name and not string.match(name, "^#") then
    local saved = {}
    ability = tonumber(string.match(rest, "ab=(%d+)") or "0")
    local function edit(addr, size, v)
      saved[#saved + 1] = { addr, size, rd(addr, size) }
      wr(addr, size, v)
    end
    for x, y, h in string.gmatch(rest, "h=(%d+),(%d+),(%d+)") do
      edit(panl + 12 + (tonumber(y) * w + tonumber(x)) * 12, 1, tonumber(h))
    end
    for a, n, v in string.gmatch(rest, "(%x+):(%d):(%w+)") do
      edit(tonumber(a, 16), tonumber(n), tonumber(v))
    end
    result = nil
    buffer = 0
    frames(2, { B = true })
    frames(SETTLE)
    frames(2, { A = true })
    frames(SETTLE)
    log:write(string.format("%s %s\n", name, result or "none"))
    log:flush()
    for i = #saved, 1, -1 do wr(saved[i][1], saved[i][2], saved[i][3]) end
  end
end
log:close()
speed.exit()
