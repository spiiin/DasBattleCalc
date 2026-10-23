-- Logs registers and stack words when the CPU reaches given addresses.
-- PROBE_EXEC = "name:0xADDR,..."; output research/exec_log.txt.
local OUT = "C:/src/DasBattleCalc/research/"
local speed = dofile(OUT .. "speed.lua")   -- fast, restores the speed on exit
local STATE = os.getenv("PROBE_STATE") or "C:/rom/BizHawk-2.11-win-x64/GBA/State/ffta_test_battle1.State"
local FRAMES = tonumber(os.getenv("PROBE_FRAMES") or "600")
local PLAN = os.getenv("PROBE_PLAN") or ""
local SHOTS = os.getenv("PROBE_SHOTS") or ""
local plan, shots = {}, {}
for f, b in string.gmatch(PLAN, "(%d+):(%a+)") do
  plan[tonumber(f)] = b
  plan[tonumber(f) + 1] = b
end
for f in string.gmatch(SHOTS, "(%d+)") do shots[tonumber(f)] = true end
local log = io.open(OUT .. "exec_log.txt", "w")
local frame = 0
local function r(n) return emu.getregister("R" .. n) end
for name, a in string.gmatch(os.getenv("PROBE_EXEC") or "", "(%w+):(0x%x+)") do
  event.on_bus_exec(function()
    local sp = r(13)
    local st = {}
    for i = 0, 7 do st[#st + 1] = string.format("%x", memory.read_u32_le(sp + i * 4, "System Bus")) end
    log:write(string.format("%5d %-8s r0=%x r1=%x r2=%x r3=%x r4=%x r5=%x r6=%x r7=%x r8=%x r9=%x r10=%x lr=%08X sp: %s\n",
      frame, name, r(0), r(1), r(2), r(3), r(4), r(5), r(6), r(7), r(8), r(9), r(10), r(14), table.concat(st, " ")))
  end, tonumber(a))
end
savestate.load(STATE)
speed.fast(800)
for f = 0, FRAMES do
  frame = f
  local b = plan[f]
  if b then joypad.set({ [b] = true }) end
  if shots[f] then client.screenshot(string.format("%sshots/e%05d.png", OUT, f)) end
  if f == 60 then
    for ad, sz, v in string.gmatch(os.getenv("PROBE_PATCHES") or "", "(0x%x+):(%d):(%d+)") do
      if tonumber(sz) == 1 then memory.write_u8(tonumber(ad), tonumber(v), "System Bus")
      else memory.write_u16_le(tonumber(ad), tonumber(v), "System Bus") end
    end
  end
  emu.frameadvance()
end
log:close()
speed.exit()
