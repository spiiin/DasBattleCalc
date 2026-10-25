-- Real Attacks: from the state at the target cursor (Luso next to
-- Sasarr, ffta2_test_attack.State), PROBE_RUNS times: load, wait k x
-- PROBE_STEP frames (moves the RNG), cursor to the target, A (forecast),
-- A (attack), wait, read the target's HP. Optional PROBE_EDITS
-- "addr:size:value ..." (hex addr) written before each attack.
-- Output: exec_log.txt, "k hp_before hp_after record_hp_after seed".
local OUT = "C:/src/DasBattleCalc/research/ffta2/"
local speed = dofile("C:/src/DasBattleCalc/research/speed.lua")
local STATE = os.getenv("PROBE_STATE") or "C:/rom/BizHawk-2.11-win-x64/NDS/State/ffta2_test_attack.State"
local RUNS = tonumber(os.getenv("PROBE_RUNS") or "40")
local STEP = tonumber(os.getenv("PROBE_STEP") or "1")
local HP = tonumber(os.getenv("PROBE_HP") or "212A104", 16)        -- Sasarr record +0x34 (the object updates later)
local EDITS = os.getenv("PROBE_EDITS") or ""
-- PROBE_HP2: another HP to log (e.g. the attacker's, record +0x34:
-- Luso 0x0212B154 - a counter-attack); PROBE_SHOTS: frames after the
-- second A to screenshot in run 0 (shots/exec_<frame>.png)
local HP2 = tonumber(os.getenv("PROBE_HP2") or "0", 16)
local SHOTS = {}
for f in string.gmatch(os.getenv("PROBE_SHOTS") or "", "%d+") do SHOTS[tonumber(f)] = true end
-- the battle RNG (0x0206F264): seed = seed x 0x5D588B65 + 0x269EC3, value =
-- seed >> 16; the seed at [0x02129A74] + 0xC944 (0x022F3F64 in this state).
-- PROBE_SEED_ADDR set: run k starts from seed k x 0x9E3779B1 + 1.
local SEED_ADDR = tonumber(os.getenv("PROBE_SEED_ADDR") or "0", 16)
-- the hit roll uses the target's own generator (0x0205E950: struct +0x10
-- seed, +0x14 multiplier, +0x18 increment; Sasarr's struct 0x022F14D0):
-- PROBE_HIT_SEED_ADDR set: run k starts it from k x 0x85EBCA6B + 7
local HIT_SEED_ADDR = tonumber(os.getenv("PROBE_HIT_SEED_ADDR") or "0", 16)
-- PROBE_PREPLAN "frame:Button,...": inputs from the load to the target cursor
-- (e.g. the whole turn from the first battle's state)
local pre, pre_end = {}, 0
for f, b in string.gmatch(os.getenv("PROBE_PREPLAN") or "", "(%d+):(%a+)") do
  pre[tonumber(f)] = b
  pre[tonumber(f) + 1] = b
  pre_end = math.max(pre_end, tonumber(f) + 60)
end

local function rd16(a) return memory.read_u16_le(a - 0x02000000, "Main RAM") end
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

local log = io.open(OUT .. "exec_log.txt", "w")
speed.fast(3200)
for k = 0, RUNS - 1 do
  savestate.load(STATE)
  for a, n, v in string.gmatch(EDITS, "(%x+):(%d):(%w+)") do wr(tonumber(a, 16), tonumber(n), tonumber(v)) end
  local seed = 0
  if SEED_ADDR ~= 0 then
    seed = (k * 0x9E3779B1 + 1) % 0x100000000
    wr(SEED_ADDR, 4, seed)
  end
  local hseed = 0
  if HIT_SEED_ADDR ~= 0 then
    hseed = (k * 0x85EBCA6B + 7) % 0x100000000
    wr(HIT_SEED_ADDR, 4, hseed)
  end
  for f = 0, pre_end do
    if pre[f] then joypad.set({ [pre[f]] = true }) end
    emu.frameadvance()
  end
  frames(1 + k * STEP)
  frames(2, { Right = true })
  frames(40)
  local before = rd16(HP)
  frames(2, { A = true })
  frames(45)
  local before2 = HP2 ~= 0 and rd16(HP2) or 0
  frames(2, { A = true })
  for f = 1, 320 do
    if k == 0 and SHOTS[f] then client.screenshot(string.format("%sshots/exec_%03d.png", OUT, f)) end
    emu.frameadvance()
  end
  if k == 0 then client.screenshot(OUT .. "shots/exec_000.png") end
  log:write(string.format("%d %d %d %d %d %d %d %d\n", k, before, rd16(HP), rd16(0x0212A104), seed, hseed,
    before2, HP2 ~= 0 and rd16(HP2) or 0))
  log:flush()
end
log:close()
speed.exit()
