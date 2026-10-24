-- The height the game shows under the cursor ("h 3.5"), for every tile:
-- frees the cursor (B), walks it over the map row by row and logs the
-- cursor tile (u16 x, y at 0x0212F01A) and the shown height x 16
-- ([0x02129A74] + 0xC938). Output: height_log.txt, "x y h16" (heights1.txt: the first battle).
local OUT = "C:/src/DasBattleCalc/research/ffta2/"
local speed = dofile("C:/src/DasBattleCalc/research/speed.lua")
local STATE = os.getenv("PROBE_STATE") or "C:/rom/BizHawk-2.11-win-x64/NDS/State/ffta2_test_battle1.State"
local W = tonumber(os.getenv("PROBE_W") or "12")
local H = tonumber(os.getenv("PROBE_H") or "12")
local function rd16(a) return memory.read_u16_le(a - 0x02000000, "Main RAM") end
local function rd32(a) return memory.read_u32_le(a - 0x02000000, "Main RAM") end
local function frames(n, key)
  for _ = 1, n do
    if key then joypad.set({ [key] = true }) end
    emu.frameadvance()
  end
end
local log = io.open(OUT .. "height_log.txt", "w")
local function record()
  local base = rd32(0x02129A74)
  local h = memory.read_s16_le(base + 0xC938 - 0x02000000, "Main RAM")
  log:write(string.format("%d %d %d\n", rd16(0x0212F01A), rd16(0x0212F01C), h))
  log:flush()
end
savestate.load(STATE)
speed.fast(3200)
frames(10)
frames(2, "B")
frames(30)
-- to the corner (0, 0)
for _ = 1, W do frames(2, "Left") frames(10) end
for _ = 1, H do frames(2, "Up") frames(10) end
for y = 0, H - 1 do
  local dir = (y % 2 == 0) and "Right" or "Left"
  for x = 0, W - 1 do
    frames(20)
    record()
    if x < W - 1 then frames(2, dir) end
  end
  frames(2, "Down")
end
log:close()
speed.exit()
