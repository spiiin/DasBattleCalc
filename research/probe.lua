-- FFTA turn-order probe for BizHawk 2.11 (mGBA core).
-- Loads QuickSave1, then runs a scripted input plan and logs, every
-- frame where anything changes, the CT (+0xD0), Speed (+0xD2) and the
-- word after it (+0xD4) of both unit arrays found in EWRAM.
-- Output: research/probe_log.txt and research/shots/fNNNNN.png.

local OUT = "C:/src/DasBattleCalc/research/"
local speed = dofile(OUT .. "speed.lua")   -- fast, restores the speed on exit
local STATE = "C:/rom/BizHawk-2.11-win-x64/GBA/State/Final Fantasy Tactics Advance (USA, Australia).mGBA.QuickSave1.State"
local FRAMES = tonumber(os.getenv("PROBE_FRAMES") or "1200")
local SHOT_EVERY = tonumber(os.getenv("PROBE_SHOT_EVERY") or "120")
-- input plan: "frame:BUTTON,frame:BUTTON" (button held 2 frames)
local PLAN = os.getenv("PROBE_PLAN") or ""

local ARRAYS = { {0x000080, 6}, {0x002fc4, 4} }   -- EWRAM offsets
local STRIDE = 0x108

local plan = {}
for f, b in string.gmatch(PLAN, "(%d+):(%a+)") do
  plan[tonumber(f)] = b
  plan[tonumber(f) + 1] = b
end

savestate.load(STATE)
speed.fast(800)
local log = io.open(OUT .. "probe_log.txt", "w")
local last = ""
for frame = 0, FRAMES do
  local b = plan[frame]
  if b then joypad.set({ [b] = true }) end
  local parts = {}
  for _, a in ipairs(ARRAYS) do
    for k = 0, a[2] - 1 do
      local base = a[1] + k * STRIDE
      local ct = memory.read_u16_le(base + 0xD0, "EWRAM")
      local sp = memory.read_u16_le(base + 0xD2, "EWRAM")
      local x = memory.read_u16_le(base + 0xD4, "EWRAM")
      parts[#parts + 1] = string.format("%d/%d/%d", ct, sp, x)
    end
  end
  local line = table.concat(parts, " ")
  if line ~= last then
    log:write(string.format("%6d %s%s\n", frame, line, b and ("  <" .. b) or ""))
    last = line
  end
  if frame % SHOT_EVERY == 0 then
    client.screenshot(string.format("%sshots/f%05d.png", OUT, frame))
  end
  emu.frameadvance()
end
log:close()
speed.exit()
