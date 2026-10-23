-- Fast runs for the probes without changing the user's BizHawk: the
-- speed settings are saved by EmuHawk into config.ini when it exits, so
-- a probe that sped up and then called client.exit() left the emulator
-- at 800-6400 % unthrottled. Usage in a probe:
--   local speed = dofile(OUT .. "speed.lua")
--   speed.fast(1600)       -- instead of client.speedmode(1600)
--   ...
--   speed.exit()           -- instead of client.exit()
local cfg = client.getconfig()
local saved = { percent = cfg.SpeedPercent, unthrottled = cfg.Unthrottled, clock = cfg.ClockThrottle }
local M = {}

function M.fast(percent)
  client.speedmode(percent)
end

-- the speed, the throttle as they were when the probe started
function M.restore()
  client.speedmode(saved.percent)
  cfg.Unthrottled = saved.unthrottled
  cfg.ClockThrottle = saved.clock
end

function M.exit()
  M.restore()
  client.exit()
end

return M
