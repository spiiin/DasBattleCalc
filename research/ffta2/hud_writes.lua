-- Where the unit panel (HP / MP / stats at 0x0212B154) gets its values:
-- cancels the command menu, moves the cursor over the field, logs every
-- write to the panel's HP word with PC, LR and R0-R12 (ARM9), and takes
-- screenshots. PROBE_PLAN "frame:Button,..."; output research/ffta2/
-- hud_log.txt, shots/hud_<frame>.png.
local OUT = "C:/src/DasBattleCalc/research/ffta2/"
local speed = dofile("C:/src/DasBattleCalc/research/speed.lua")
local STATE = os.getenv("PROBE_STATE") or "C:/rom/BizHawk-2.11-win-x64/NDS/State/ffta2_test_battle1.State"
local PLAN = os.getenv("PROBE_PLAN") or "10:B,40:Left,60:Left,80:Left,100:Up,120:Up,140:Right,160:Right,180:Down"
local FRAMES = tonumber(os.getenv("PROBE_FRAMES") or "220")
local SHOTS = os.getenv("PROBE_SHOTS") or "35,75,115,155,215"
os.execute('mkdir "' .. (OUT .. "shots"):gsub("/", "\\") .. '" 2>nul')
local plan, shots = {}, {}
for f, b in string.gmatch(PLAN, "(%d+):(%a+)") do
  plan[tonumber(f)] = b
  plan[tonumber(f) + 1] = b
end
for f in string.gmatch(SHOTS, "%d+") do shots[tonumber(f)] = true end
local log = io.open(OUT .. "hud_log.txt", "w")
local frame = 0
local function r(n) return emu.getregister("ARM9 r" .. n) end
event.on_bus_write(function(addr, v)
  local regs = {}
  for i = 0, 12 do regs[#regs + 1] = string.format("r%d=%08X", i, r(i)) end
  log:write(string.format("%3d write %08X v=%08X pc=%08X lr=%08X %s\n", frame, addr, v or 0, r(15), r(14),
    table.concat(regs, " ")))
end, 0x0212B154)
savestate.load(STATE)
speed.fast(800)
for f = 0, FRAMES do
  frame = f
  if plan[f] then joypad.set({ [plan[f]] = true }) end
  if shots[f] then client.screenshot(string.format("%sshots/hud_%03d.png", OUT, f)) end
  emu.frameadvance()
end
log:close()
speed.exit()
