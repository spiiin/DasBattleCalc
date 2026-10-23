-- Long FFTA battle log for validating the turn-order model.
-- Units are taken from the participant wrappers. Every frame in which
-- a CT / reserve value changes, logs one line per unit:
--   frame idx record ct reserve speed status(E8..ED) items(5) b104
-- A macro presses buttons so player turns end with Wait.
local OUT = "C:/src/DasBattleCalc/research/"
local STATE = os.getenv("PROBE_STATE") or
  "C:/rom/BizHawk-2.11-win-x64/GBA/State/Final Fantasy Tactics Advance (USA, Australia).mGBA.QuickSave1.State"
local FRAMES = tonumber(os.getenv("PROBE_FRAMES") or "20000")
local SHOT_EVERY = tonumber(os.getenv("PROBE_SHOT_EVERY") or "600")

-- participants: the wrapper array (stride 0x90, [0] = unit record)
local WRAPPERS = tonumber(os.getenv("PROBE_WRAPPERS") or "0x020223AC")
local function rd32b(a) return memory.read_u32_le(a, "System Bus") end
local function units()
  local list = {}
  for k = 0, 11 do
    local rec = rd32b(WRAPPERS + k * 0x90)
    if rec < 0x02000000 or rec >= 0x02040000 then break end
    if rd32b(rec) ~= 0 then list[#list + 1] = rec end
  end
  return list
end
local function rd8(a) return memory.read_u8(a, "System Bus") end
local function rd16(a) return memory.read_u16_le(a, "System Bus") end
local function rd32(a) return memory.read_u32_le(a, "System Bus") end

-- Wait macro: B B (cancel), A (menu), Down Down, A (Wait), A A (confirm)
local MACRO = { {0, "B"}, {10, "B"}, {20, "A"}, {40, "Down"}, {50, "Down"}, {60, "A"}, {90, "A"}, {120, "A"} }
local PERIOD = 300

savestate.load(STATE)
client.speedmode(1600)
local log = io.open(OUT .. "long_log.txt", "w")
local last = ""
for frame = 0, FRAMES do
  local t = frame % PERIOD
  for _, m in ipairs(MACRO) do
    if t == m[1] or t == m[1] + 1 then joypad.set({ [m[2]] = true }) end
  end
  do
    local recs = units()
    local n = #recs
    local key = {}
    for i = 1, n do
      local rec = recs[i]
      key[#key + 1] = rd16(rec + 0xD0) .. "," .. rd16(rec + 0xD4)
    end
    local k = table.concat(key, " ")
    if k ~= last then
      last = k
      log:write(string.format("F %d %d\n", frame, n))
      for i = 1, n do
        local rec = recs[i]
        local st = {}
        for b = 0xE8, 0xED do st[#st + 1] = string.format("%02x", rd8(rec + b)) end
        local it = {}
        for s = 0, 4 do it[#it + 1] = tostring(rd16(rec + 0x2A + s * 2)) end
        log:write(string.format("U %d %08x %d %d %d %s %s %d %08x\n", i, rec, rd16(rec + 0xD0),
          rd16(rec + 0xD4), rd16(rec + 0xD2), table.concat(st, ""), table.concat(it, ","),
          rd8(rec + 0x104), rd32(rec)))
      end
    end
  end
  if frame % SHOT_EVERY == 0 then
    client.screenshot(string.format("%sshots/l%05d.png", OUT, frame))
  end
  emu.frameadvance()
end
log:close()
client.exit()
