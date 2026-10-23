-- Loads a state written by the app (export_battle) and logs what the game
-- has in RAM for every participant, then plays PROBE_FRAMES frames with
-- PROBE_PLAN buttons and takes screenshots: does the game accept it?
-- PROBE_STATE (the exported file), PROBE_LOG, PROBE_SHOTS (prefix).
local OUT = "C:/src/DasBattleCalc/research/"
local STATE = os.getenv("PROBE_STATE")
local FRAMES = tonumber(os.getenv("PROBE_FRAMES") or "120")
local SHOTS = os.getenv("PROBE_SHOTS") or (OUT .. "export_shot")
local plan = {}
for f, b in string.gmatch(os.getenv("PROBE_PLAN") or "", "(%d+):(%a+)") do
  plan[tonumber(f)] = b
  plan[tonumber(f) + 1] = b
end
local log = io.open(OUT .. (os.getenv("PROBE_LOG") or "export_check_log.txt"), "w")
local function rd8(a) return memory.read_u8(a, "System Bus") end
local function rd16(a) return memory.read_u16_le(a, "System Bus") end
local function rd32(a) return memory.read_u32_le(a, "System Bus") end
local function dump(tag)
  local w = 0x020223AC
  while true do
    local rec = rd32(w)
    if rec < 0x02000000 or rec >= 0x02040000 then break end
    log:write(string.format("%s rec %08x hp %d/%d mp %d watk %d spd %d ct %d items %d,%d sup %d rea %d st %02x%02x%02x%02x%02x%02x pos %d,%d h %d f %d\n",
      tag, rec, rd16(rec + 0x18), rd16(rec + 0x1A), rd16(rec + 0x1C), rd16(rec + 0x20), rd16(rec + 0xD2), rd16(rec + 0xD0),
      rd16(rec + 0x2A), rd16(rec + 0x2C), rd8(rec + 0x3B), rd8(rec + 0x3A),
      rd8(rec + 0xE8), rd8(rec + 0xE9), rd8(rec + 0xEA), rd8(rec + 0xEB), rd8(rec + 0xEC), rd8(rec + 0xED),
      rd16(w + 8) >> 5, rd16(w + 0xC) >> 5, rd16(w + 0xA) >> 4, rd8(w + 0x1F)))
    w = w + 0x90
  end
end
client.speedmode(800)
savestate.load(STATE)
dump("load")
for f = 0, FRAMES do
  local b = plan[f]
  if b then joypad.set({ [b] = true }) end
  if f % tonumber(os.getenv("PROBE_EVERY") or "60") == 0 then client.screenshot(string.format("%s_%03d.png", SHOTS, f)) end
  emu.frameadvance()
end
dump("after")
log:close()
client.exit()
