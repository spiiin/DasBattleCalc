-- RAM before and after Luso moves (to find the unit records by the
-- position change): dumps Main RAM at PROBE_BEFORE and PROBE_AFTER frames,
-- runs PROBE_PLAN, takes screenshots. Output: research/ffta2/
-- move_before.bin, move_after.bin, shots/move_<frame>.png.
local OUT = "C:/src/DasBattleCalc/research/ffta2/"
local speed = dofile("C:/src/DasBattleCalc/research/speed.lua")
local STATE = os.getenv("PROBE_STATE") or "C:/rom/BizHawk-2.11-win-x64/NDS/State/ffta2_test_battle1.State"
local PLAN = os.getenv("PROBE_PLAN") or "10:A,50:Left,80:A,140:A"
local BEFORE = tonumber(os.getenv("PROBE_BEFORE") or "5")
local AFTER = tonumber(os.getenv("PROBE_AFTER") or "300")
local SHOTS = os.getenv("PROBE_SHOTS") or "45,75,110,170,300"
os.execute('mkdir "' .. (OUT .. "shots"):gsub("/", "\\") .. '" 2>nul')
local plan, shots = {}, {}
for f, b in string.gmatch(PLAN, "(%d+):(%a+)") do
  plan[tonumber(f)] = b
  plan[tonumber(f) + 1] = b
end
for f in string.gmatch(SHOTS, "%d+") do shots[tonumber(f)] = true end
local function dump(file)
  local f = io.open(OUT .. file, "wb")
  for a = 0, 0x400000 - 1, 0x10000 do
    local bytes = memory.read_bytes_as_array(a, 0x10000, "Main RAM")
    local parts = {}
    for i = 1, #bytes do parts[i] = string.char(bytes[i]) end
    f:write(table.concat(parts))
  end
  f:close()
end
savestate.load(STATE)
speed.fast(800)
for f = 0, AFTER do
  if f == BEFORE then dump("move_before.bin") end
  if plan[f] then joypad.set({ [plan[f]] = true }) end
  if shots[f] then client.screenshot(string.format("%sshots/move_%03d.png", OUT, f)) end
  emu.frameadvance()
end
dump("move_after.bin")
speed.exit()
