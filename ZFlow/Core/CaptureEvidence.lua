-- What a feature run on a capture shows, and what it does not. Offline only;
-- not tested in game. Lua 5.1, no game API.
--
-- A capture (Core/Capture.lua) holds the saved tables, a few reads and the
-- shapes of some calls. It does not hold the quest log, spells, auras, a
-- target, bag items, a bank or flight map, or the screen. So a feature's
-- words typed on a capture alone mostly say "nothing to work on": that is a
-- smoke test (no Lua error), not a check of the feature.
--
-- Each run is judged one of four ways:
--   captured       its behaviour showed, on inputs from the capture only
--   synthetic      its behaviour showed, with inputs the test made up; each
--                  is named
--   not exercised  its behaviour did not show: what was missing is named.
--                  NEVER a pass.
--   error          a Lua problem while it ran
--
--   Evidence.REQUIRES[feature]  what that feature's run needs (below)
--   Evidence.Judge(feature, run) -> verdict
--       run = { cap, report (Capture.Apply's), lines, problems (count),
--               synthetic = { name, ... } the test supplied, addon }
--       verdict = { feature, result, verified (bool), smoke (bool),
--                   missing = {}, synthetic = {}, recorded (bool) }
--   Evidence.Text(verdicts) -> lines, in the add-on's own words only: no
--       line or value of a capture is in them
--   Evidence.Count(verdicts) -> { captured, synthetic, notExercised, error }
local _, ns = ...

local Evidence = {}
ns.CaptureEvidence = Evidence

Evidence.CAPTURED, Evidence.SYNTHETIC = "captured", "synthetic"
Evidence.NOT_EXERCISED, Evidence.ERROR = "not exercised", "error"

-- What the capture can give beyond Capture.READS.
Evidence.SNAPSHOT, Evidence.SAVED_SETTINGS = "a snapshot", "saved settings"
Evidence.NOTHING_SAID = "any line from it"
Evidence.NO_BEHAVIOUR = "a line showing its behaviour"
-- A proves check that raised: the check did not run, so nothing is shown.
Evidence.CHECK_FAILED = "a check of the add-on that ran without a Lua error"
-- A problem count that is not a number: not known, so never zero.
Evidence.PROBLEMS_UNKNOWN = "a count of Lua problems while it ran"

-- Per feature (the names of Capture.FEATURES):
--   asserts   what a verified run shows
--   captured  inputs the capture can give: Capture.READS names, "a
--             snapshot", "saved settings"
--   outside   inputs no capture holds: a test must make them up and say so
--   supplies  inputs the feature's own words make up (a preview command):
--             always counted as synthetic
--   recorded  false: the run can never stand for the recorded thing in the
--             real game (a preview of a flight is not a flight taken)
--   idle      words the feature says when it had nothing to work on, each
--             with what was missing
--   shows     words one of which a line must hold for the behaviour to have
--             shown; none: any line that is not idle
--   proves    function(run) -> true | false, what is missing: a check on
--             the add-on instead of on lines; one that raises is not a
--             verification (CHECK_FAILED)
Evidence.REQUIRES = {
    rotation = {
        asserts = "the rotation line of the diag word gives a suggestion, or the reason there is none",
        captured = { "class", "level" },
        outside = { "known spells", "a target" },
        idle = {
            ["rotation: switched off"] = "the rotation setting on",
            ["rotation: no reading yet"] = "a rotation reading",
            ["rotation: not running"] = "the rotation running",
        },
        shows = { "rotation: " },
    },
    arrow = {
        asserts = "the arrow says which quest step it points at and where that came from",
        captured = { "position", "zone" },
        outside = { "the quest log" },
        idle = {
            ["quest step from nothing"] = "a quest step",
            ["quest log: not read"] = "the quest log",
            ["not known where you are"] = "position",
        },
        shows = { "quest step from " },
    },
    flights = {
        asserts = "Travel gives a way by flight for a made-up far quest step (a preview, not a flight taken)",
        captured = { "position", "zone" },
        -- A capture holds a map's size but not where the map lies in the
        -- world, and Travel cannot measure a flight without that.
        outside = { "the map's place in the world" },
        supplies = { "a made-up far quest step (preview command)", "a made-up flight point (preview command)" },
        recorded = false,
        idle = {
            ["Travel has no shortcut for it"] = "the map's place in the world",
            ["Travel is not running"] = "Travel running",
            ["the flight way is not running"] = "the flight way running",
            ["your place is not known"] = "position",
            ["your continent is not known"] = "zone",
            ["Preview: not started yet"] = "the preview started",
        },
        shows = { "Preview: Travel says: " },
    },
    banker = {
        asserts = "the banker lists what in the bags to put in the bank",
        captured = {},
        outside = { "bag items" },
        idle = {
            ["the bags have not been read yet"] = "bag items",
            ["banker: not started yet"] = "the banker started",
        },
        -- The bank list header (Items/Present.lua BANK_HEADER): only a
        -- list shows the banker at work. The other banker lines (bank not
        -- seen, nothing to bank) are said with or without bag items.
        shows = { "To bank (" },
    },
    settings = {
        asserts = "a setting saved in the capture reads back through the add-on's settings",
        captured = { "saved settings" },
        outside = {},
        proves = function(run)
            local cap, addon = run.cap, run.addon
            local saved = type(cap) == "table" and type(cap.account) == "table" and cap.account.settings or nil
            local settings = type(addon) == "table" and addon.settings or nil
            if type(saved) ~= "table" or type(settings) ~= "table" or type(settings.each) ~= "function" then
                return false, Evidence.SAVED_SETTINGS
            end
            local read, wrong = 0, 0
            for row in settings:each() do
                -- Only rows kept at "settings." .. key in the account, of a
                -- plain kind: a row with its own place is not judged here.
                if type(row) == "table" and type(row.key) == "string" and row.scope == "account" and row.path == nil then
                    local at = saved
                    for seg in row.key:gmatch("[^%.]+") do
                        if type(at) == "table" then at = at[seg] else at = nil end
                    end
                    if type(at) == "boolean" or type(at) == "number" or type(at) == "string" then
                        local ok, v = pcall(settings.get, settings, row.key)
                        read = read + 1
                        if not ok or v ~= at then wrong = wrong + 1 end
                    end
                end
            end
            if read == 0 then return false, "a saved setting the add-on has a row for" end
            if wrong > 0 then return false, "the saved value read back (" .. wrong .. " did not)" end
            return true
        end,
    },
}

local function setOf(list)
    local out = {}
    for _, name in ipairs(type(list) == "table" and list or {}) do out[tostring(name)] = true end
    return out
end

local function add(list, seen, name)
    if not seen[name] then
        seen[name] = true
        list[#list + 1] = name
    end
end

-- What the capture gave: the reads Capture.Apply set, a snapshot, saved
-- settings (a non-empty settings table in the account).
function Evidence.Have(cap, report)
    local have = setOf(type(report) == "table" and report.set or nil)
    if ns.Capture.Newest(cap) ~= nil then have[Evidence.SNAPSHOT] = true end
    local settings = type(cap) == "table" and type(cap.account) == "table" and cap.account.settings or nil
    if type(settings) == "table" and next(settings) ~= nil then have[Evidence.SAVED_SETTINGS] = true end
    return have
end

-- Whether a feature's captured inputs come from a snapshot (the reads do;
-- saved settings do not).
local function needsSnapshot(spec)
    for _, name in ipairs(spec.captured) do
        if name ~= Evidence.SAVED_SETTINGS then return true end
    end
    return false
end

function Evidence.Judge(feature, run)
    run = type(run) == "table" and run or {}
    local spec = Evidence.REQUIRES[feature]
    local lines = type(run.lines) == "table" and run.lines or {}
    -- A count that is not a number is not known: never read as zero.
    local problems = type(run.problems) == "number" and run.problems == run.problems and run.problems or nil
    local v = { feature = tostring(feature), missing = {}, synthetic = {}, verified = false,
        smoke = problems == 0, recorded = false }
    if not spec then
        v.result, v.missing = Evidence.NOT_EXERCISED, { "a requirement list for this feature" }
        return v
    end
    if problems == nil then
        v.result, v.missing = Evidence.NOT_EXERCISED, { Evidence.PROBLEMS_UNKNOWN }
        return v
    end
    if problems > 0 then
        v.result = Evidence.ERROR
        return v
    end

    local have, made = Evidence.Have(run.cap, run.report), setOf(run.synthetic)
    local missSeen, synSeen = {}, {}
    -- Anything the test made up is named, whether the feature lists it or
    -- not: one made-up input and the run is no longer on the capture alone.
    for _, name in ipairs(type(run.synthetic) == "table" and run.synthetic or {}) do
        add(v.synthetic, synSeen, tostring(name))
    end
    for _, name in ipairs(spec.supplies or {}) do add(v.synthetic, synSeen, name) end
    if needsSnapshot(spec) and not have[Evidence.SNAPSHOT] and not made[Evidence.SNAPSHOT] then
        add(v.missing, missSeen, Evidence.SNAPSHOT)
    end
    for _, name in ipairs(spec.captured) do
        if not have[name] and not made[name] then add(v.missing, missSeen, name) end
    end
    for _, name in ipairs(spec.outside) do
        if not made[name] then add(v.missing, missSeen, name) end
    end

    -- Then what the run itself showed: an idle line names what it lacked,
    -- whatever the test says it supplied.
    if spec.proves then
        local ran, ok, why = pcall(spec.proves, run)
        if not ran then
            add(v.missing, missSeen, Evidence.CHECK_FAILED)
        elseif not ok then
            add(v.missing, missSeen, tostring(why or Evidence.NO_BEHAVIOUR))
        end
    else
        local shown = false
        for _, line in ipairs(lines) do
            local text, idle = tostring(line), false
            for words, lack in pairs(spec.idle or {}) do
                if text:find(words, 1, true) then
                    idle = true
                    add(v.missing, missSeen, lack)
                end
            end
            if not idle then
                if spec.shows then
                    for _, words in ipairs(spec.shows) do
                        if text:find(words, 1, true) then shown = true end
                    end
                else
                    shown = true
                end
            end
        end
        if #lines == 0 then
            add(v.missing, missSeen, Evidence.NOTHING_SAID)
        elseif not shown then
            add(v.missing, missSeen, Evidence.NO_BEHAVIOUR)
        end
    end
    table.sort(v.missing)

    if #v.missing > 0 then
        v.result = Evidence.NOT_EXERCISED
        return v
    end
    v.verified = true
    v.result = #v.synthetic > 0 and Evidence.SYNTHETIC or Evidence.CAPTURED
    v.recorded = v.result == Evidence.CAPTURED and spec.recorded ~= false
    return v
end

function Evidence.Count(verdicts)
    local n = { captured = 0, synthetic = 0, notExercised = 0, error = 0 }
    for _, v in ipairs(verdicts or {}) do
        if v.result == Evidence.CAPTURED then n.captured = n.captured + 1
        elseif v.result == Evidence.SYNTHETIC then n.synthetic = n.synthetic + 1
        elseif v.result == Evidence.ERROR then n.error = n.error + 1
        else n.notExercised = n.notExercised + 1 end
    end
    return n
end

-- One line per verdict. Only this file's words and the feature's name.
function Evidence.Text(verdicts)
    local out = {}
    for _, v in ipairs(verdicts or {}) do
        local line
        if v.result == Evidence.CAPTURED then
            line = v.feature .. ": verified on captured inputs"
        elseif v.result == Evidence.SYNTHETIC then
            line = v.feature .. ": verified with made-up inputs (" .. table.concat(v.synthetic, "; ") .. ")"
            if not v.recorded then line = line .. "; not a recorded real-game result" end
        elseif v.result == Evidence.ERROR then
            line = v.feature .. ": Lua problem while it ran; not verified"
        else
            line = v.feature .. ": NOT exercised; missing " .. table.concat(v.missing, "; ")
            if v.smoke then line = line .. " (it ran with no Lua problem: a smoke test only)" end
        end
        out[#out + 1] = line
    end
    return out
end
