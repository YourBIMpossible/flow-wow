local _, ns = ...
-- G59 (lead sections 226, 243, 244): the three game options, each a setting
-- of the module (not one of Model.ROWS), off by default, with a topic and
-- the words the settings search finds. The texts never spell the old name.
-- Made-up values only. Not tested in game.
local tests = {}

local KEYS = { cameraZoom = "game.cameraZoom", chatTimes = "game.chatTimes", combatLogFile = "game.combatLogFile" }

local function rows()
    local spec
    local G = ns.GameOptions
    if type(G) ~= "table" or type(G.Declare) ~= "function" then return nil end
    G.Declare({ Module = function(_, m) spec = m end })
    local out = {}
    for _, row in ipairs(type(spec) == "table" and spec.settings or {}) do out[row.key] = row end
    return out, spec
end

tests["game options: three rows, off by default, account wide, yes or no"] = function(t)
    local byKey = rows()
    t.ok(byKey ~= nil, "the module declares its rows")
    if not byKey then return end
    for _, key in pairs(KEYS) do
        local row = byKey[key] or {}
        t.eq({ row.key, row.type, row.default, row.scope }, { key, "bool", false, "account" }, key)
        t.ok(type(row.label) == "string" and row.label ~= "", key .. " label")
        t.ok(type(row.help) == "string" and row.help ~= "", key .. " help")
        t.ok(not tostring(row.label):find("Flow", 1, true) and not tostring(row.help):find("Flow", 1, true),
            key .. " never spells Flow")
    end
end

tests["game options 244: each row names its topic and lists words to find it"] = function(t)
    local byKey = rows()
    if not byKey then t.ok(false, "rows"); return end
    t.eq((byKey[KEYS.cameraZoom] or {}).group, "general")
    t.eq((byKey[KEYS.chatTimes] or {}).group, "general")
    t.eq((byKey[KEYS.combatLogFile] or {}).group, "combat")
    local want = { [KEYS.cameraZoom] = "camera", [KEYS.chatTimes] = "timestamps", [KEYS.combatLogFile] = "combat log" }
    for key, word in pairs(want) do
        local found = false
        for _, w in ipairs((byKey[key] or {}).synonyms or {}) do if w == word then found = true end end
        t.ok(found, key .. " is found by " .. word)
    end
end

tests["game options 243: the rows are the module's own, not in Model.ROWS"] = function(t)
    for _, row in ipairs(ns.Settings.Model.ROWS) do
        for _, key in pairs(KEYS) do t.ok(row.key ~= key, key .. " is not a Model row") end
    end
end

tests["game options: the module needs the client, the store and the settings, and acts on no event"] = function(t)
    local _, spec = rows()
    if type(spec) ~= "table" then t.ok(false, "spec"); return end
    local needs = {}
    for _, n in ipairs(spec.needs or {}) do needs[n] = true end
    t.ok(needs.client and needs.store and needs.settings, "needs")
    t.eq(spec.events, nil, "no game event drives a change")
end

tests["game options: the camera ladder is tried farthest first"] = function(t)
    t.eq(ns.GameOptions and ns.GameOptions.CAMERA_STEPS, { "4", "3.4", "2.6" })
    t.eq(ns.GameOptions and ns.GameOptions.CHAT_FORMAT, "%H:%M:%S ")
end

return tests
