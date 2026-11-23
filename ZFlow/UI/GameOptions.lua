local _, ns = ...
-- G59 (lead section 226): three game options, each a setting, off until the
-- player chooses. What the old add-on did was read (Modules/Camera.lua,
-- Chat.lua, CombatLogFile.lua); nothing is copied.
--   game.cameraZoom     the farthest camera distance: the first of 4, 3.4
--                       and 2.6 the game keeps
--   game.chatTimes      chat timestamps as hours:minutes:seconds
--   game.combatLogFile  the game writes the combat log to its file
-- Turned on by the player (the settings page or the setting word), the
-- value the game had is kept (account "learned.gameOptions"); turned off,
-- or reset, that value is put back and then forgotten. A put-back the game
-- refuses keeps the value for the next try. Nothing changes at login, at a
-- reload or on any tick: the store watch fires only when the value
-- changes. A value the game does not say is never guessed: nothing is
-- changed and the line says so.
-- ACTS: the writes are client.setGameSetting and client.setCombatLogFile, on the
-- player's own choice only. A client without them changes nothing.
-- Needs game test: every read and write, a write in a fight, the camera
-- limit the game keeps, the value text the game answers.
local G = {}
ns.GameOptions = G

G.NAME = "gameOptions"
G.PATH = "learned.gameOptions"   -- account: the values found, by option
G.CAMERA = "cameraDistanceMaxZoomFactor"
G.STAMPS = "showTimestamps"
G.CAMERA_STEPS = { "4", "3.4", "2.6" }
G.CHAT_FORMAT = "%H:%M:%S "

-- The value kept for an option ("cameraZoom", "chatTimes",
-- "combatLogFile"), or nil. false is a value (the log file was off).
function G.Found(k, opt)
    if type(k) ~= "table" or type(k.store) ~= "table" or type(opt) ~= "string" then return nil end
    return k.store:get("account", G.PATH .. "." .. opt)
end

-- Same value: the same text, or the same number the game wrote out longer.
local function same(a, b)
    if a == b then return true end
    local x, y = tonumber(a), tonumber(b)
    return x ~= nil and x == y
end

-- A write through the client: true, or nil and why ("noCall", "raised" or
-- what the client said).
local function act(fn, ...)
    if type(fn) ~= "function" then return nil, "noCall" end
    local ok, done, why = pcall(fn, ...)
    if not ok then return nil, "raised" end
    if done == true then return true end
    return nil, why or "bad"
end

-- Writes a setting and reads it back: true when the game kept it (or does
-- not say), nil and why when not.
local function putGameSetting(cl, name, v)
    local ok, why = act(cl.setGameSetting, name, v)
    if not ok then return nil, why end
    local now = cl.gameSetting(name)
    if now == nil or same(now, v) then return true end
    return nil, "kept"
end

local function stampsText(v)
    if v == "none" or v == "" then return "off" end
    return "\"" .. tostring(v) .. "\""
end

local function onOff(v) return v and "on" or "off" end

local OPTIONS = {
    {
        opt = "cameraZoom", key = "game.cameraZoom", name = "Camera distance", group = "general",
        label = "Pull the camera farther back",
        help = "Lets the camera zoom out farther than the game normally allows. Turning it off puts back the "
            .. "distance you had.",
        synonyms = { "camera", "zoom", "distance", "view" },
        show = tostring,
        read = function(cl) return cl.gameSetting(G.CAMERA) end,
        apply = function(cl)
            local why
            for _, v in ipairs(G.CAMERA_STEPS) do
                local ok, w = putGameSetting(cl, G.CAMERA, v)
                if ok then return v end
                why = w
                if w ~= "kept" then break end
            end
            return nil, why
        end,
        put = function(cl, v) return putGameSetting(cl, G.CAMERA, v) end,
    },
    {
        opt = "chatTimes", key = "game.chatTimes", name = "Chat timestamps", group = "general",
        label = "Chat timestamps",
        help = "Shows the time, as hours:minutes:seconds, before each chat line. Turning it off puts back the "
            .. "timestamps you had.",
        synonyms = { "chat", "timestamps", "time", "clock" },
        show = stampsText,
        read = function(cl) return cl.gameSetting(G.STAMPS) end,
        apply = function(cl)
            local ok, why = putGameSetting(cl, G.STAMPS, G.CHAT_FORMAT)
            if ok then return G.CHAT_FORMAT end
            return nil, why
        end,
        put = function(cl, v) return putGameSetting(cl, G.STAMPS, v) end,
    },
    {
        opt = "combatLogFile", key = "game.combatLogFile", name = "Combat log file", group = "combat",
        label = "Write the combat log to a file",
        help = "Has the game write your combat log to its log file, for fight review sites. Turning it off "
            .. "stops the file only if it was off before.",
        synonyms = { "combat log", "log", "file", "logging", "fights" },
        show = onOff,
        read = function(cl) return cl.combatLogFile() end,
        apply = function(cl)
            local ok, why = act(cl.setCombatLogFile, true)
            if ok then return true end
            return nil, why
        end,
        put = function(cl, v) return act(cl.setCombatLogFile, v) end,
    },
}

local WHY = {
    noCall = "the game has no call for it here",
    raised = "the game refused the change",
    bad = "the game refused the change",
    kept = "the game kept its own value",
}
local function because(why) return WHY[why] or WHY.bad end

function G.Declare(k)
    local ctx
    local cancels = {}
    local api = {}

    local function say(text)
        if ctx and ctx.client and type(ctx.client.print) == "function" then
            ctx.client.print((ns.id and ns.id.title or "") .. ": " .. text)
        end
    end
    local function path(o) return G.PATH .. "." .. o.opt end

    -- The player turned it on: keep what the game has (once), then change it.
    local function turnOn(o)
        local cl = ctx.client
        local found = ctx.store:get("account", path(o))
        if found == nil then
            local ok, now = pcall(o.read, cl)
            if not ok or now == nil then
                say(o.name .. " not changed: the game did not say its value, so it could not be put back.")
                return
            end
            found = now
            ctx.store:set("account", path(o), found)
        end
        local ok, done, why = pcall(o.apply, cl)
        if not ok then done, why = nil, "raised" end
        if done == nil then
            say(o.name .. " not changed (" .. because(why) .. "). It stays " .. o.show(found) .. ".")
            return
        end
        say(o.name .. " set to " .. o.show(done) .. " (it was " .. o.show(found)
            .. "; turning the setting off puts that back).")
    end

    -- Off, or reset: put back what was kept; forget it once it is back.
    local function turnOff(o)
        local cl = ctx.client
        local found = ctx.store:get("account", path(o))
        if found == nil then return end
        local okR, now = pcall(o.read, cl)
        if okR and now ~= nil and same(now, found) then
            ctx.store:set("account", path(o), nil)
            say(o.name .. " left " .. o.show(found) .. ", as it was before.")
            return
        end
        local ok, done, why = pcall(o.put, cl, found)
        if not ok then done, why = nil, "raised" end
        if done ~= true then
            say(o.name .. " not put back to " .. o.show(found) .. " (" .. because(why)
                .. "). It is kept for the next try.")
            return
        end
        ctx.store:set("account", path(o), nil)
        say(o.name .. " put back to " .. o.show(found) .. ".")
    end

    function api.status()
        local out = {}
        if not ctx then return out end
        for _, o in ipairs(OPTIONS) do
            out[o.opt] = { on = ctx.settings:get(o.key) == true, kept = G.Found(k, o.opt) ~= nil }
        end
        return out
    end

    local rows = {}
    for _, o in ipairs(OPTIONS) do
        rows[#rows + 1] = {
            key = o.key, scope = "account", type = "bool", default = false,
            label = o.label, help = o.help, group = o.group, synonyms = o.synonyms,
        }
    end

    k:Module({
        name = G.NAME,
        needs = { "client", "store", "settings" },
        settings = rows,
        provides = { Status = api.status },
        start = function(c)
            ctx = c
            for _, o in ipairs(OPTIONS) do
                local row = c.settings:row(o.key)
                if type(row) == "table" then
                    local cancel = c.store:watch(row.scope, row.path or ("settings." .. o.key), function(value, old)
                        if value == true and old ~= true then
                            turnOn(o)
                        elseif value ~= true and old == true then
                            turnOff(o)
                        end
                    end)
                    if type(cancel) == "function" then cancels[#cancels + 1] = cancel end
                end
            end
        end,
        stop = function()
            for i = 1, #cancels do cancels[i]() end
            cancels = {}
            ctx = nil
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.gameOptions = G.Declare(ns)
