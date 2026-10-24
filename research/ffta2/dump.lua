-- FFTA2 (NDS, melonDS core): dumps the memory domains of a state.
-- PROBE_STATE (default: the battle test save); output research/ffta2/
-- domains.txt and <domain>.bin for Main RAM, ARM9 / shared WRAM.
local OUT = "C:/src/DasBattleCalc/research/ffta2/"
local speed = dofile("C:/src/DasBattleCalc/research/speed.lua")
local STATE = os.getenv("PROBE_STATE") or "C:/rom/BizHawk-2.11-win-x64/NDS/State/ffta2_test_battle1.State"
local FRAMES = tonumber(os.getenv("PROBE_FRAMES") or "0")

savestate.load(STATE)
for _ = 1, FRAMES do emu.frameadvance() end
local log = io.open(OUT .. "domains.txt", "w")
for _, name in ipairs(memory.getmemorydomainlist()) do
  log:write(string.format("%s %d\n", name, memory.getmemorydomainsize(name)))
end
log:close()
local function dump(domain, file)
  local size = memory.getmemorydomainsize(domain)
  local f = io.open(OUT .. file, "wb")
  local chunk = 0x10000
  for a = 0, size - 1, chunk do
    local n = math.min(chunk, size - a)
    local bytes = memory.read_bytes_as_array(a, n, domain)
    local parts = {}
    for i = 1, #bytes do parts[i] = string.char(bytes[i]) end
    f:write(table.concat(parts))
  end
  f:close()
end
dump("Main RAM", "mainram.bin")
speed.exit()
