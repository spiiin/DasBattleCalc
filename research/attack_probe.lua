-- Attack preview of Marc -> Montblanc (Fight) under RAM patches: for
-- each case the state is reloaded, the patches written before the
-- preview, and the game's own damage (0x0813023C r0) and hit chance
-- (0x0812C8C6 r0) are logged. PROBE_CASES = "name=addr:size:val;...|..."
-- ("copy0xSRC>0xDST" copies a 0x108-byte unit record).
local OUT = "C:/src/DasBattleCalc/research/"
local speed = dofile(OUT .. "speed.lua")   -- fast, restores the speed on exit
local STATE = os.getenv("PROBE_STATE") or "C:/rom/BizHawk-2.11-win-x64/GBA/State/ffta_test_battle1.State"
local PLAN = { [90] = "A", [130] = "Down", [150] = "A", [200] = "A", [300] = "Left", [360] = "A" }
-- PROBE_PLAN "frame:Button,...": other presses (second battle, Loki's
-- menu already open: 20:Down,40:A,80:A,140:Right,180:A)
if os.getenv("PROBE_PLAN") then
  PLAN = {}
  for f, b in string.gmatch(os.getenv("PROBE_PLAN"), "(%d+):(%a+)") do PLAN[tonumber(f)] = b end
end
local log = io.open(OUT .. (os.getenv("PROBE_LOG") or "attack_probe_log.txt"), "w")
local dmg, hit = "-", "-"
event.on_bus_exec(function() dmg = tostring(emu.getregister("R0")) end, 0x0813023C)
event.on_bus_exec(function() hit = tostring(emu.getregister("R0")) end, 0x0812C8C6)
speed.fast(1600)
for case in string.gmatch(os.getenv("PROBE_CASES") or "base=", "[^|]+") do
  local name, patches = string.match(case, "([^=]*)=(.*)")
  savestate.load(STATE)
  dmg, hit = "-", "-"
  for f = 0, 400 do
    local b = PLAN[f] or PLAN[f - 1]
    if b then joypad.set({ [b] = true }) end
    if f == tonumber(os.getenv("PROBE_PATCH_AT") or "250") then
      for src, dst in string.gmatch(patches, "copy(0x%x+)>(0x%x+)") do
        local from, to = tonumber(src), tonumber(dst)
        for i = 0, 0x107 do memory.write_u8(to + i, memory.read_u8(from + i, "System Bus"), "System Bus") end
      end
      for a, s, v in string.gmatch(patches, "(0x%x+):(%d):(%d+)") do
        local addr, size, val = tonumber(a), tonumber(s), tonumber(v)
        if size == 1 then memory.write_u8(addr, val, "System Bus") else memory.write_u16_le(addr, val, "System Bus") end
      end
    end
    emu.frameadvance()
  end
  log:write(string.format("%s dmg=%s hit=%s\n", name, dmg, hit))
end
log:close()
speed.exit()
