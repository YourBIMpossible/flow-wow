local F = {}
local function whole(n) return math.floor(n + 0.5) end
function F.Length(f) return whole(f.ended - f.started) .. "s" end
function F.Wait(secs) return "in " .. secs .. " s" end
return F
