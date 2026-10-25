-- FFT (PSX) generic probe: loads the state, plays an input plan, takes
-- screenshots and dumps the main RAM at given frames.
--   PROBE_STATE  the state (default: the first battle, fft_test_battle1)
--   PROBE_PLAN   "frame:Button,..." (a button is held 2 frames; Button+Button
--                presses both). PSX pad: Up Down Left Right Cross Circle
--                Square Triangle L1 R1 L2 R2 Start Select (P1 prefixed)
--   PROBE_SHOTS  frames to screenshot: shots/plan_<frame>.png
--   PROBE_DUMPS  frames to dump the main RAM: plan_<frame>.bin
--   PROBE_FRAMES the last frame
--   PROBE_EDITS  "addr:size:value ..." (hex main RAM offset) after the load
--   PROBE_SAVE   "frame:path": save a state at that frame
local OUT = "C:/src/DasBattleCalc-psx/research/fft/"
local STATE = os.getenv("PROBE_STATE") or "C:/rom/BizHawk-2.11-win-x64/PSX/State/fft_test_battle1.State"
local PLAN = os.getenv("PROBE_PLAN") or ""
local SHOTS = os.getenv("PROBE_SHOTS") or ""
local DUMPS = os.getenv("PROBE_DUMPS") or ""
local FRAMES = tonumber(os.getenv("PROBE_FRAMES") or "300")
local SAVE = os.getenv("PROBE_SAVE") or ""
-- BizHawk's names of the (DualShock) pad buttons
local PAD = { Up = "P1 D-Pad Up", Down = "P1 D-Pad Down", Left = "P1 D-Pad Left", Right = "P1 D-Pad Right",
  Cross = "P1 X", Circle = "P1 \u{25CB}", Square = "P1 \u{25A1}", Triangle = "P1 \u{25B3}" }
local plan, shots, dumps = {}, {}, {}
for f, b in string.gmatch(PLAN, "(%d+):([%w%+]+)") do
  local keys = {}
  for k in string.gmatch(b, "%w+") do keys[PAD[k] or ("P1 " .. k)] = true end
  plan[tonumber(f)] = keys
  plan[tonumber(f) + 1] = keys
end
for f in string.gmatch(SHOTS, "%d+") do shots[tonumber(f)] = true end
for f in string.gmatch(DUMPS, "%d+") do dumps[tonumber(f)] = true end
local save_frame, save_path = string.match(SAVE, "(%d+):(.+)")
save_frame = tonumber(save_frame)
local function dump(file)
  local f = io.open(OUT .. file, "wb")
  for a = 0, 0x200000 - 1, 0x10000 do
    local bytes = memory.read_bytes_as_array(a, 0x10000, "MainRAM")
    local parts = {}
    for i = 1, #bytes do parts[i] = string.char(bytes[i]) end
    f:write(table.concat(parts))
  end
  f:close()
end
savestate.load(STATE)
for a, n, v in string.gmatch(os.getenv("PROBE_EDITS") or "", "(%x+):(%d):(%w+)") do
  local addr, size, val = tonumber(a, 16), tonumber(n), tonumber(v)
  if size == 1 then memory.write_u8(addr, val, "MainRAM")
  elseif size == 2 then memory.write_u16_le(addr, val, "MainRAM")
  else memory.write_u32_le(addr, val, "MainRAM") end
end
client.speedmode(800)
for f = 0, FRAMES do
  if plan[f] then joypad.set(plan[f]) end
  if dumps[f] then dump(string.format("plan_%03d.bin", f)) end
  if shots[f] then client.screenshot(string.format("%sshots/plan_%03d.png", OUT, f)) end
  if save_frame == f then savestate.save(save_path) end
  emu.frameadvance()
end
client.exit()
