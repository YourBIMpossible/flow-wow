-- N68: the one alert sound (UI/Alerts.lua). The real client over a
-- hand-built environment.
--   c.playAlert() -> true | nil, why
--       PlaySound(SOUNDKIT.RAID_WARNING). why: "noCall" (no PlaySound, or
--       no such sound named by the game: no number is guessed), "raised".
-- Sound only: nothing in the game is changed.
-- Needs game test: the call and the sound name on 16001.
local _, ns = ...

local tests = {}

local function recorder(raise)
    local calls = {}
    local fn = function(...)
        calls[#calls + 1] = { ... }
        if raise then error("no") end
        return true
    end
    return fn, calls
end

tests["c.playAlert: the raid warning sound the game names"] = function(t)
    local fn, calls = recorder(false)
    local c = ns.make.client({ PlaySound = fn, SOUNDKIT = { RAID_WARNING = 8959 } })
    if type(c.playAlert) ~= "function" then t.ok(false, "c.playAlert"); return end
    t.eq({ c.playAlert() }, { true })
    t.eq(calls, { { 8959 } }, "one call, the sound only")
end

tests["c.playAlert: no call or no sound name: nothing played, no number guessed"] = function(t)
    local fn, calls = recorder(false)
    local none = ns.make.client({ SOUNDKIT = { RAID_WARNING = 8959 } })
    if type(none.playAlert) ~= "function" then t.ok(false, "c.playAlert"); return end
    t.eq({ none.playAlert() }, { nil, "noCall" }, "no PlaySound")
    local noKit = ns.make.client({ PlaySound = fn })
    t.eq({ noKit.playAlert() }, { nil, "noCall" }, "no SOUNDKIT")
    local noName = ns.make.client({ PlaySound = fn, SOUNDKIT = {} })
    t.eq({ noName.playAlert() }, { nil, "noCall" }, "no RAID_WARNING")
    t.eq(#calls, 0, "the game is not asked")
end

tests["c.playAlert: a sound name that is not a number: nothing played (AL-1)"] = function(t)
    local fn, calls = recorder(false)
    for _, v in ipairs({ false, "RAID_WARNING", true }) do
        local c = ns.make.client({ PlaySound = fn, SOUNDKIT = { RAID_WARNING = v } })
        if type(c.playAlert) ~= "function" then t.ok(false, "c.playAlert"); return end
        t.eq({ c.playAlert() }, { nil, "noCall" }, tostring(v))
    end
    t.eq(#calls, 0, "the game is not asked")
end

tests["c.playAlert: a call that raises"] = function(t)
    local fn, calls = recorder(true)
    local c = ns.make.client({ PlaySound = fn, SOUNDKIT = { RAID_WARNING = 8959 } })
    if type(c.playAlert) ~= "function" then t.ok(false, "c.playAlert"); return end
    t.eq({ c.playAlert() }, { nil, "raised" })
    t.eq(#calls, 1)
end

tests["c.playAlert: the names are on the diag name list"] = function(t)
    local found = {}
    for _, name in ipairs(ns.Diag.NAMES) do found[name] = true end
    t.ok(found.PlaySound == true, "PlaySound")
    t.ok(found["SOUNDKIT.RAID_WARNING"] == true, "SOUNDKIT.RAID_WARNING")
end

return tests
