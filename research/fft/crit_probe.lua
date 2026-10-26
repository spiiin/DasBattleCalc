-- FFT (PSX): the outcome of Ramza's Attack at Lezales, many times: each
-- trial loads fft_test_ramza2, sets the RNG's seed (0x80009010, PsyQ
-- rand: seed x 0x41C64E6D + 0x3039; idling does not move it) to its own
-- value, attacks (Act > Attack > the tile below > Execute) and reads
-- Lezales' HP after the hit: a miss, the forecast's 42, or more (a
-- critical). One line per trial in crit.txt: seed, HP before, HP after.
--   CRIT_TRIALS (200), CRIT_FIRST (0: the first trial's number - its seed)
local OUT = "C:/src/DasBattleCalc-psx/research/fft/"
local STATE = os.getenv("PROBE_STATE") or "C:/rom/BizHawk-2.11-win-x64/PSX/State/fft_test_ramza2.State"
local TRIALS = tonumber(os.getenv("CRIT_TRIALS") or "200")
local FIRST = tonumber(os.getenv("CRIT_FIRST") or "0")
local LEZ = 0x19118C          -- Lezales' record (slot 5); HP at +0x28
local PAD = { Down = "P1 D-Pad Down", Circle = "P1 \u{25CB}" }
-- CRIT_EXEC: a state saved at "Execute?" (the plan below skipped) - each
-- trial then is the seed, one Circle and the frames until the HP moves
local EXEC = os.getenv("CRIT_EXEC")
local PLAN = EXEC and { [5] = "Circle" } or { [10] = "Down", [30] = "Circle", [60] = "Circle", [90] = "Circle",
  [130] = "Down", [165] = "Circle", [230] = "Circle", [280] = "Circle" }
local LAST = EXEC and 800 or 1000
local f = io.open(OUT .. "crit.txt", "w")
client.speedmode(1600)
for t = FIRST, FIRST + TRIALS - 1 do
  savestate.load(EXEC or STATE)
  local k = (t * 2654435761 + 12345) % 4294967296
  memory.write_u32_le(0x009010, k, "MainRAM")
  local before = memory.read_u16_le(LEZ + 0x28, "MainRAM")
  for fr = 0, LAST do
    local b = PLAN[fr] or PLAN[fr - 1]
    if b then joypad.set({ [PAD[b]] = true }) end
    emu.frameadvance()
    if fr > 5 and memory.read_u16_le(LEZ + 0x28, "MainRAM") ~= before then break end
  end
  local after = memory.read_u16_le(LEZ + 0x28, "MainRAM")
  f:write(string.format("%d %d %d\n", k, before, after))
  f:flush()
end
f:close()
client.exit()
