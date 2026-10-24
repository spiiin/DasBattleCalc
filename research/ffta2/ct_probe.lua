-- CT over time: plays PROBE_PLAN ("frame:Button,...") from PROBE_STATE and
-- logs every change of the battle objects' CT (+0x16), HP (+0x08) and
-- position (+0x0C, +0x0D) - objects of 0x48 bytes from PROBE_OBJECTS
-- (default 0x02129AA0, the first battle), PROBE_COUNT of them.
-- Output: ct_log.txt, "frame object field old new"; shots/ct_<frame>.png at PROBE_SHOTS.
local OUT = "C:/src/DasBattleCalc/research/ffta2/"
local speed = dofile("C:/src/DasBattleCalc/research/speed.lua")
local STATE = os.getenv("PROBE_STATE") or "C:/rom/BizHawk-2.11-win-x64/NDS/State/ffta2_test_battle1.State"
local PLAN = os.getenv("PROBE_PLAN") or ""
local FRAMES = tonumber(os.getenv("PROBE_FRAMES") or "3000")
local BASE = tonumber(os.getenv("PROBE_OBJECTS") or "2129AA0", 16) - 0x02000000
local COUNT = tonumber(os.getenv("PROBE_COUNT") or "7")
local SHOTS = os.getenv("PROBE_SHOTS") or ""
local plan, shots = {}, {}
for f, b in string.gmatch(PLAN, "(%d+):(%a+)") do
  plan[tonumber(f)] = b
  plan[tonumber(f) + 1] = b
end
for f in string.gmatch(SHOTS, "%d+") do shots[tonumber(f)] = true end
local fields = { { "ct", 0x16, 2 }, { "hp", 0x08, 2 }, { "x", 0x0C, 1 }, { "y", 0x0D, 1 }, { "face", 0x0E, 1 } }
local function rd(a, n)
  if n == 1 then return memory.read_u8(a, "Main RAM") end
  return memory.read_u16_le(a, "Main RAM")
end
local last = {}
local log = io.open(OUT .. "ct_log.txt", "w")
savestate.load(STATE)
-- PROBE_EDITS "addr:size:value ..." (hex addr): written after the load
for a, n, v in string.gmatch(os.getenv("PROBE_EDITS") or "", "(%x+):(%d):(%w+)") do
  local addr, size, val = tonumber(a, 16) - 0x02000000, tonumber(n), tonumber(v)
  if size == 1 then memory.write_u8(addr, val, "Main RAM")
  else memory.write_u16_le(addr, val, "Main RAM") end
end
speed.fast(3200)
for f = 0, FRAMES do
  if plan[f] then joypad.set({ [plan[f]] = true }) end
  for k = 0, COUNT - 1 do
    for _, fd in ipairs(fields) do
      local key = k .. fd[1]
      local v = rd(BASE + k * 0x48 + fd[2], fd[3])
      if last[key] ~= v then
        log:write(string.format("%d %d %s %s %d\n", f, k, fd[1], tostring(last[key]), v))
        last[key] = v
      end
    end
  end
  if shots[f] then client.screenshot(string.format("%sshots/ct_%04d.png", OUT, f)) end
  emu.frameadvance()
end
log:close()
speed.exit()
