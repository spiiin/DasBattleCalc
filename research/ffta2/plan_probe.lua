-- A generic probe: loads the state, plays an input plan, takes screenshots
-- and dumps Main RAM at given frames.
--   PROBE_STATE  the state (default: the first battle)
--   PROBE_PLAN   "frame:Button,..." (a button is held 2 frames; Button+Button
--                presses both)
--   PROBE_SHOTS  frames to screenshot: shots/plan_<frame>.png
--   PROBE_DUMPS  frames to dump Main RAM: plan_<frame>.bin (and the ITCM,
--                0x01FF8000 for the VM helpers: plan_<frame>_itcm.bin)
--   PROBE_FRAMES the last frame
--   PROBE_SAVE   "frame:path": save a state at that frame
--   PROBE_WATCH  ARM9 addresses (hex, comma separated): every write is
--                logged with PC, LR and R0..R12 to plan_log.txt
--   PROBE_EXEC   ARM9 code addresses: every execution is logged the same way
--   PROBE_READ   ARM9 addresses: every read (from frame PROBE_FROM) is logged
local OUT = "C:/src/DasBattleCalc/research/ffta2/"
local speed = dofile("C:/src/DasBattleCalc/research/speed.lua")
local STATE = os.getenv("PROBE_STATE") or "C:/rom/BizHawk-2.11-win-x64/NDS/State/ffta2_test_battle1.State"
local PLAN = os.getenv("PROBE_PLAN") or ""
local SHOTS = os.getenv("PROBE_SHOTS") or ""
local DUMPS = os.getenv("PROBE_DUMPS") or ""
local FRAMES = tonumber(os.getenv("PROBE_FRAMES") or "300")
local SAVE = os.getenv("PROBE_SAVE") or ""
os.execute('mkdir "' .. (OUT .. "shots"):gsub("/", "\\") .. '" 2>nul')
local plan, shots, dumps = {}, {}, {}
for f, b in string.gmatch(PLAN, "(%d+):([%a%+]+)") do
  local keys = {}
  for k in string.gmatch(b, "%a+") do keys[k] = true end
  plan[tonumber(f)] = keys
  plan[tonumber(f) + 1] = keys
end
for f in string.gmatch(SHOTS, "%d+") do shots[tonumber(f)] = true end
for f in string.gmatch(DUMPS, "%d+") do dumps[tonumber(f)] = true end
local log = io.open(OUT .. "plan_log.txt", "w")
local frame = 0
local function r(n) return emu.getregister("ARM9 r" .. n) end
local function log_regs(what, addr, v)
  local regs = {}
  for i = 0, 12 do regs[#regs + 1] = string.format("r%d=%08X", i, r(i)) end
  log:write(string.format("%3d %s %08X v=%08X pc=%08X lr=%08X sp=%08X %s\n", frame, what, addr, v or 0, r(15), r(14),
    r(13), table.concat(regs, " ")))
end
for a in string.gmatch(os.getenv("PROBE_WATCH") or "", "%x+") do
  event.on_bus_write(function(addr, v) log_regs("write", addr, v) end, tonumber(a, 16))
end
for a in string.gmatch(os.getenv("PROBE_READ") or "", "%x+") do
  event.on_bus_read(function(addr) if frame >= tonumber(os.getenv("PROBE_FROM") or "0") then log_regs("read", addr, 0) end end, tonumber(a, 16))
end
for a in string.gmatch(os.getenv("PROBE_EXEC") or "", "%x+") do
  event.on_bus_exec(function(addr) log_regs("exec", addr, 0) end, tonumber(a, 16))
end
local save_frame, save_path = string.match(SAVE, "(%d+):(.+)")
save_frame = tonumber(save_frame)
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
-- PROBE_EDITS "addr:size:value ..." (hex addr): written after the load
for a, n, v in string.gmatch(os.getenv("PROBE_EDITS") or "", "(%x+):(%d):(%w+)") do
  local addr, size, val = tonumber(a, 16) - 0x02000000, tonumber(n), tonumber(v)
  if size == 1 then memory.write_u8(addr, val, "Main RAM")
  elseif size == 2 then memory.write_u16_le(addr, val, "Main RAM")
  else memory.write_u32_le(addr, val, "Main RAM") end
end
speed.fast(800)
for f = 0, FRAMES do
  frame = f
  if plan[f] then joypad.set(plan[f]) end
  if dumps[f] then
    dump(string.format("plan_%03d.bin", f))
    local t = io.open(string.format("%splan_%03d_itcm.bin", OUT, f), "wb")
    local bytes = memory.read_bytes_as_array(0, 0x8000, "Instruction TCM")
    local parts = {}
    for i = 1, #bytes do parts[i] = string.char(bytes[i]) end
    t:write(table.concat(parts))
    t:close()
  end
  if shots[f] then client.screenshot(string.format("%sshots/plan_%03d.png", OUT, f)) end
  if save_frame == f then savestate.save(save_path) end
  emu.frameadvance()
end
log:close()
speed.exit()
