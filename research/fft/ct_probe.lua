-- FFT (PSX): CT over time. Plays PROBE_PLAN ("frame:Button,...", buttons
-- as plan_probe.lua) from PROBE_STATE and logs every change of the battle
-- records' CT (+0x39), HP (+0x28), x / y (+0x47 / +0x48) and +0x49 for
-- the 21 slots at 0x801908CC. Output: ct_log.txt "frame slot field old
-- new"; shots/ct_<frame>.png at PROBE_SHOTS.
local OUT = "C:/src/DasBattleCalc-psx/research/fft/"
local STATE = os.getenv("PROBE_STATE") or "C:/rom/BizHawk-2.11-win-x64/PSX/State/fft_test_battle1.State"
local PLAN = os.getenv("PROBE_PLAN") or ""
local FRAMES = tonumber(os.getenv("PROBE_FRAMES") or "3000")
local SHOTS = os.getenv("PROBE_SHOTS") or ""
local PAD = { Up = "P1 D-Pad Up", Down = "P1 D-Pad Down", Left = "P1 D-Pad Left", Right = "P1 D-Pad Right",
  Cross = "P1 X", Circle = "P1 \u{25CB}", Square = "P1 \u{25A1}", Triangle = "P1 \u{25B3}" }
local plan, shots = {}, {}
for f, b in string.gmatch(PLAN, "(%d+):([%w%+]+)") do
  local keys = {}
  for k in string.gmatch(b, "%w+") do keys[PAD[k] or ("P1 " .. k)] = true end
  plan[tonumber(f)] = keys
  plan[tonumber(f) + 1] = keys
end
for f in string.gmatch(SHOTS, "%d+") do shots[tonumber(f)] = true end
local BASE = 0x1908CC
local fields = { { "ct", 0x39, 1 }, { "hp", 0x28, 2 }, { "x", 0x47, 1 }, { "y", 0x48, 1 }, { "f49", 0x49, 1 } }
local last, pend, since = {}, {}, {}
local STABLE = tonumber(os.getenv("PROBE_STABLE") or "5")
local log = io.open(OUT .. "ct_log.txt", "w")
savestate.load(STATE)
client.speedmode(1600)
for f = 0, FRAMES do
  if plan[f] then joypad.set(plan[f]) end
  for k = 0, 20 do
    local rec = BASE + k * 0x1C0
    if memory.read_u8(rec + 1, "MainRAM") ~= 0xFF then
      for _, fd in ipairs(fields) do
        local key = k .. fd[1]
        local v = fd[3] == 1 and memory.read_u8(rec + fd[2], "MainRAM") or memory.read_u16_le(rec + fd[2], "MainRAM")
        -- the AI tries moves by writing them for a frame or two: a change
        -- counts when the value stays STABLE frames
        if pend[key] ~= v then
          pend[key] = v
          since[key] = f
        elseif last[key] ~= v and f - since[key] >= STABLE then
          -- the unit taking its turn (0x8016D004 points at its record)
          local act = memory.read_u32_le(0x16D004, "MainRAM")
          local who = (act >= 0x801908CC and act < 0x801908CC + 21 * 0x1C0) and (act - 0x801908CC) // 0x1C0 or -1
          log:write(string.format("%d %d %s %s %d by %d\n", since[key], k, fd[1], tostring(last[key]), v, who))
          last[key] = v
        end
      end
    end
  end
  if shots[f] then client.screenshot(string.format("%sshots/ct_%04d.png", OUT, f)) end
  emu.frameadvance()
end
log:close()
client.exit()
