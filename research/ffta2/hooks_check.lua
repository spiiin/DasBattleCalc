-- Do BizHawk's memory callbacks work with the melonDS core? Samples the
-- ARM9 PC while the battle save runs, hooks execution there and writes of
-- the DS frame counter (0x027FFC3C), and counts the calls.
-- Output: research/ffta2/hooks_log.txt.
local OUT = "C:/src/DasBattleCalc/research/ffta2/"
local speed = dofile("C:/src/DasBattleCalc/research/speed.lua")
local STATE = os.getenv("PROBE_STATE") or "C:/rom/BizHawk-2.11-win-x64/NDS/State/ffta2_test_battle1.State"
local log = io.open(OUT .. "hooks_log.txt", "w")
local counts = {}
local function bump(k) counts[k] = (counts[k] or 0) + 1 end
savestate.load(STATE)
speed.fast(800)
local pcs = {}
for f = 1, 20 do
  emu.frameadvance()
  pcs[#pcs + 1] = emu.getregister("ARM9 r15")
end
log:write("sampled ARM9 pc:")
for _, pc in ipairs(pcs) do log:write(string.format(" %08X", pc)) end
log:write("\n")
local ok, err = pcall(function()
  for i = 1, 5 do
    local pc = pcs[i]
    event.on_bus_exec(function() bump(string.format("exec %08X", pc)) end, pc)
  end
  event.on_bus_write(function() bump("write 027FFC3C") end, 0x027FFC3C)
  event.on_bus_read(function() bump("read 027FFC3C") end, 0x027FFC3C)
  event.on_bus_write(function() bump("write HP 0212B154") end, 0x0212B154)
end)
log:write("register hooks: " .. tostring(ok) .. " " .. tostring(err) .. "\n")
for f = 1, 60 do emu.frameadvance() end
for k, v in pairs(counts) do log:write(k .. " " .. v .. "\n") end
log:write("done\n")
log:close()
speed.exit()
