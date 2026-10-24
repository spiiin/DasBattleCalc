-- The attack forecast for edited units: from the state at the target
-- cursor (Luso next to Sasarr, ffta2_test_attack.State), per line of
-- PROBE_CASES (a file): write the edits into Main RAM, confirm the target
-- (A), read the forecast, go back (B), restore the edits.
--   case line: name addr:size:value ...   (addr hex, size 1 / 2 / 4, value dec or 0x)
-- Output: vary_log.txt, "name hit damage".
local OUT = "C:/src/DasBattleCalc/research/ffta2/"
local speed = dofile("C:/src/DasBattleCalc/research/speed.lua")
local STATE = os.getenv("PROBE_STATE") or "C:/rom/BizHawk-2.11-win-x64/NDS/State/ffta2_test_attack.State"
local CASES = os.getenv("PROBE_CASES") or (OUT .. "cases.txt")
local FORECAST = tonumber(os.getenv("PROBE_FORECAST") or "2292FC6", 16)   -- u16 damage, u16 hit
local SETTLE = tonumber(os.getenv("PROBE_SETTLE") or "40")

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

local log = io.open(OUT .. "vary_log.txt", "w")
savestate.load(STATE)
speed.fast(1600)
frames(5)
-- the cursor onto the target once
frames(2, { Right = true })
frames(SETTLE)
for line in io.lines(CASES) do
  local name, rest = string.match(line, "^(%S+)%s*(.*)$")
  if name and not string.match(name, "^#") then
    local saved = {}
    for a, n, v in string.gmatch(rest, "(%x+):(%d):(%w+)") do
      local addr, size = tonumber(a, 16), tonumber(n)
      saved[#saved + 1] = { addr, size, rd(addr, size) }
      wr(addr, size, tonumber(v))
    end
    frames(2, { A = true })
    frames(SETTLE)
    log:write(string.format("%s %d %d\n", name, rd(FORECAST + 2, 2), rd(FORECAST, 2)))
    log:flush()
    frames(2, { B = true })
    frames(SETTLE)
    for i = #saved, 1, -1 do wr(saved[i][1], saved[i][2], saved[i][3]) end
  end
end
client.screenshot(OUT .. "shots/vary_last.png")
log:close()
speed.exit()
