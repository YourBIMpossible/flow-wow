local _, ns = ...
-- GameSuggest: the game's own settings this add-on suggests while levelling,
-- and the one click that sets them all (row F-14, lead section 828.4). Pure
-- Lua 5.1: no frames, no saved variable; the client is handed in.
--
-- Which settings: the old add-on's suggested rows (Modules/Setup.lua at
-- b657e6e5, lines 41-196), kept only where this add-on already reads or
-- writes the same setting on the 16001 client (UI/SetupList.lua S.GAME,
-- UI/GameOptions.lua). The rest wait for a capture that shows 16001 has
-- them. Never a key binding, never a graphics or video setting. Each why
-- is our own words.
--
-- NOTHING CHANGES ON ITS OWN. Apply runs only from the player's click; it
-- is not called at load, on a timer or at login. In a fight, or when the
-- fight is not known, it writes nothing (some settings are protected then).
--
--   GameSuggest.LIST                 { name, value, why } in the order shown
--   GameSuggest.Current(list, client) -> rows { name, value, why, now, matches }
--       now: the game's value as text, nil when not said; matches: true,
--       false, or nil when not known. Reads only (client.gameSetting).
--   GameSuggest.Apply(list, client)  -> result
--       result[i] = { name, value, result = "applied" | "refused" | "noCall", why }
--       result.applied = how many took; result.refused = "combat" when
--       nothing was asked. One client.setGameSetting per setting, each in
--       a pcall.
-- Needs game test on 16001: each write, and the refusal in a fight.

ns.Settings = ns.Settings or {}
local G = {}
ns.Settings.GameSuggest = G

G.LIST = {
    { name = "autoLootDefault", value = "1",
      why = "One click on a corpse picks up everything on it." },
    { name = "nameplateShowEnemies", value = "1",
      why = "A bar over each enemy, where quest marks sit." },
    { name = "instantQuestText", value = "1",
      why = "Quest text shows at once instead of scrolling in." },
    { name = "autoSelfCast", value = "1",
      why = "With no friend targeted, a heal or buff lands on you." },
    { name = "statusText", value = "1",
      why = "Health and mana as numbers on your frames, not only bars." },
    { name = "showTimestamps", value = "%H:%M:%S ",
      why = "Each chat line shows the time it came in." },
    { name = "cameraDistanceMaxZoomFactor", value = "4",
      why = "The camera pulls further back, so you see more around you." },
}

local function entries(list)
    if type(list) == "table" then return list end
    return {}
end

function G.Current(list, client)
    local out = {}
    local read
    if type(client) == "table" then read = client.gameSetting end
    for i, e in ipairs(entries(list)) do
        local row = { name = e.name, value = e.value, why = e.why }
        if type(read) == "function" then
            local ok, v = pcall(read, e.name)
            if ok and type(v) == "string" then row.now = v end
        end
        if row.now ~= nil then row.matches = (row.now == e.value) end
        out[i] = row
    end
    return out
end

function G.Apply(list, client)
    local out = { applied = 0 }
    local fight = true
    if type(client) == "table" and type(client.inCombat) == "function" then
        local ok, v = pcall(client.inCombat)
        if ok and v == false then fight = false end
    end
    if fight then
        out.refused = "combat"
        return out
    end
    local write = client.setGameSetting
    for i, e in ipairs(entries(list)) do
        local row = { name = e.name, value = e.value }
        if type(write) ~= "function" then
            row.result = "noCall"
        else
            local ok, done, why = pcall(write, e.name, e.value)
            if not ok then
                row.result, row.why = "refused", "raised"
            elseif done == true then
                row.result = "applied"
                out.applied = out.applied + 1
            elseif why == "noCall" then
                row.result = "noCall"
            else
                row.result, row.why = "refused", why or "bad"
            end
        end
        out[i] = row
    end
    return out
end
