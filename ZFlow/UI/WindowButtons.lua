-- Window buttons (U-E, S22): one Z-Flow button on the world map and one on
-- the merchant window. Both are ON by default: the world map's since
-- zflow-default-on, the merchant's since lead section 294 item 3
-- (UI/Rows.lua). A player who turns one off keeps it off.
--
-- LOOK ONLY. A button is a plain, non-secure button on the window. A click
-- only shows a Z-Flow panel:
--   world map  -> the arrow menu   (the "arrow" module's OpenMenu())
--   merchant   -> the sell list    (the "sellList" module's Show())
-- PROVIDER NEEDs: those two functions are the arrow's (Lazy) and the sell
-- list's (Modular) to add to their modules' `provides`. Until they are
-- there a click does nothing and is recorded as a problem.
--
-- No button is made on a window that is missing, or while the player is in
-- combat; one wanted in combat is made when combat ends. A button that
-- could not be made is tried again when its window opens (its `retry`
-- event) and when combat ends: the owner turned the merchant button on,
-- opened a merchant and saw none (section 132). A protected window, or
-- one that will not say, stops it again (section 134), and the reason
-- is said; Core/Client.lua says why. A button is made once and only
-- shown or hidden after that.
--
--   WindowButtons.WINDOWS            the two windows: key, frame, setting row,
--                                    label, what a click opens, the button spec
--   WindowButtons.Declare(k) -> api  declares the module on kernel k
--     api.state() -> { worldMap = s, merchant = s }, s one of
--       "off", "shown", "waiting for combat to end", "not made"
--     api.reasons() -> { [key] = why } for each button not made: what the
--       client said ("no window", "in combat", "no frame", "bad ask",
--       "its window is protected",
--       "its window will not say whether it is protected") or
--       "no window read" when the client has none
--     api.lines() -> one line for each window, for the chat window: the
--       state and why, then what the client says of the window itself
--       (there or not, open or closed, protected or not), then whether a
--       shown button can be seen
--   WindowButtons.Declare(k, diag) also adds the word WB.WORD, which
--   prints those lines.
--
-- Settings: "buttons.worldMap" and "buttons.merchant" (bool, account,
-- default on). The rows are UI/Rows.lua's;
-- a missing row is off.
--
-- Reads (through the injected client):
--   client.windowButton(frameName, spec) -> h | nil    CLIENT NEED
--     spec = { name = global name, text = short label, tip = tooltip line,
--              point = { anchor, relative anchor, x, y } against the window,
--              inside = { field name, ... } (optional): the point is
--              against the first of these parts of the window instead;
--              none there: nil and why. strata (optional) }
--     h.placedOn: the part used, nil for the window itself
--     nil and why when _G[frameName] is missing or InCombatLockdown() is
--     not a plain false. h is a plain Button, a child of the window
--     (shown only while the window is): h.onClick(fn) fn() on a left click,
--     h.show(on). It never sets an attribute and is never secure.
--     Fake: c.setWindow(frameName, { protected = bool }) says a window exists.
--   client.windowState(frameName) -> nil (no such window) or
--     { shown = true / false / nil, protected = true / false / nil }
--   h.visible() -> true / false / nil: can the button be seen now
--   client.inCombat()     true / false / nil (nil counts as in combat)
--   PLAYER_REGEN_ENABLED  combat ended
--   MERCHANT_SHOW, PLAYER_ENTERING_WORLD   a button not made is tried again
local _, ns = ...

local WB = ns.WindowButtons or {}
ns.WindowButtons = WB

WB.NAME = "windowButtons"
WB.WORD = "buttons"
WB.HELP = "say whether each window button is shown, and why not"
WB.NO_READ = "no window read"
-- What the client says when the part a place names is not there
-- (Core/Client.lua, windowButton): the next place is tried.
WB.NO_PLACE = "its place inside the window was not found"

-- The places a window's button is asked for, in order: win.places, or the
-- one place of win.point and win.inside.
function WB.Places(win)
    if type(win.places) == "table" then return win.places end
    return { { point = win.point, inside = win.inside } }
end

-- What the buttons line says of the place a part names, or nil.
function WB.PlaceSays(win, field)
    if field == nil then return nil end
    for _, place in ipairs(WB.Places(win)) do
        for _, name in ipairs(type(place.inside) == "table" and place.inside or {}) do
            if name == field then return place.says end
        end
    end
    return nil
end

-- Lead section 296: the buttons word also lists Plexy's other surfaces,
-- each on or off and, in one line, when it appears (its module's WHEN),
-- and why the minimap pin is not shown. mod is the module's table in ns;
-- field names its setting; off = true for a setting that hides it.
WB.SURFACES = {
    { says = "threat on enemy nameplates", mod = "PlateThreat", field = "OFF", off = true },
    { says = "combo points on your target's nameplate", mod = "PlateCombo", field = "OFF", off = true },
    { says = "quest marks on enemy nameplates", mod = "PlateQuests", field = "OFF", off = true },
    { says = "ring on the flight map", mod = "TaxiMark", field = "SETTING" },
    { says = "flight pins on the world map", mod = "MapFlights", field = "SETTING" },
    { says = "NPCs read aloud", mod = "NpcSpeech", field = "SETTING" },
}
WB.PIN_SAYS = "minimap pin"
WB.PIN_WHEN = "it appears when you set a waypoint"

-- The merchant point was seen in game (section 142): top right of the
-- merchant window, nothing over it. The world map point is a first
-- guess, not seen in game. The owner saw the first one (top right of the
-- window) under the quest log header (section 142), and the second (the
-- map's bottom right corner, 44 px in) under the quest log "Q" toggle
-- (lead section 293). So the button now stands on the toggle itself: its
-- bottom right on the toggle's top right, 4 px up, as legacy Flow's map
-- button stood (Modules/Nav/MapOverlay.lua:1176-1186), whatever the
-- toggle's size. A client with no toggle gets the map's corner. Places
-- are tried in order; a place whose part is missing gives way to the next.
-- What sits in the other corners: WoW\from-twin\RESEARCH-worldmap-button.md.
-- Needs game test. The button text
-- and the start of its tooltip are the addon's title from the identity
-- (Core/Identity.lua is the only file that may hold it).
WB.WINDOWS = {
    {
        key = "worldMap", frame = "WorldMapFrame", setting = "buttons.worldMap",
        label = "Button on the world map", says = "world map",
        retry = "PLAYER_ENTERING_WORLD",
        opens = "arrow", call = "OpenMenu",
        tip = "open the arrow menu",
        strata = "HIGH",
        places = {
            { inside = { "SidePanelToggle" }, says = "above the quest log toggle",
                point = { "BOTTOMRIGHT", "TOPRIGHT", 0, 4 } },
            { inside = { "ScrollContainer" }, says = "on the map itself",
                point = { "BOTTOMRIGHT", "BOTTOMRIGHT", -44, 4 } },
        },
    },
    {
        key = "merchant", frame = "MerchantFrame", setting = "buttons.merchant",
        label = "Button on the merchant window", says = "merchant window",
        retry = "MERCHANT_SHOW",
        opens = "sellList", call = "Show",
        tip = "show the sell list",
        point = { "TOPRIGHT", "TOPRIGHT", -40, -40 },
    },
}

function WB.Declare(k, diag)
    local api = {}
    local handles, states, reasons = {}, {}, {}
    local ctx
    local cancels = {}
    for _, win in ipairs(WB.WINDOWS) do states[win.key] = "off" end

    function api.state()
        local out = {}
        for key, s in pairs(states) do out[key] = s end
        return out
    end

    function api.reasons()
        local out = {}
        for key, why in pairs(reasons) do out[key] = why end
        return out
    end

    -- What the client says of the window itself, whatever the button is.
    local function windowSays(win)
        local client = ctx and ctx.client or k.client
        if type(client) ~= "table" or type(client.windowState) ~= "function" then return "window not read" end
        local ok, w = pcall(client.windowState, win.frame)
        if not ok then return "window not read" end
        if type(w) ~= "table" then return "window not there" end
        local s = "window there"
        if w.shown ~= nil then s = s .. (w.shown and ", open" or ", closed") end
        if w.protected == true then return s .. ", protected" end
        if w.protected == false then return s .. ", not protected" end
        return s .. ", will not say whether it is protected"
    end

    function api.lines()
        local out = {}
        for _, win in ipairs(WB.WINDOWS) do
            local s = states[win.key]
            local line = "button on the " .. win.says .. ": " .. tostring(s)
            if s == "not made" and reasons[win.key] then line = line .. " (" .. reasons[win.key] .. ")" end
            line = line .. "; " .. windowSays(win)
            local h = handles[win.key]
            if s == "shown" and h and type(h.visible) == "function" then
                local okV, v = pcall(h.visible)
                if okV and v == true then line = line .. "; button can be seen" end
                if okV and v == false then line = line .. "; button cannot be seen" end
            end
            local says = (s == "shown" and h) and WB.PlaceSays(win, h.placedOn) or nil
            if says then line = line .. "; placed " .. says end
            out[#out + 1] = line .. "."
        end
        return out
    end

    -- The lines for WB.SURFACES and the minimap pin, after the buttons'.
    function api.surfaceLines()
        local out = {}
        local settings = ctx and ctx.settings or k.settings
        for _, s in ipairs(WB.SURFACES) do
            local mod = ns[s.mod]
            if type(mod) == "table" and type(mod.WHEN) == "string" then
                local on = nil
                if type(settings) == "table" and type(mod[s.field]) == "string" then
                    local okG, v = pcall(settings.get, settings, mod[s.field])
                    if okG and type(v) == "boolean" then
                        if s.off then on = not v else on = v end
                    end
                end
                local state = on == nil and "not known" or (on and "on" or "off")
                out[#out + 1] = s.says .. ": " .. state .. "; " .. mod.WHEN
            end
        end
        local pin = k.use("minimapPin")
        local okL, last = false, nil
        if type(pin) == "table" and type(pin.Last) == "function" then okL, last = pcall(pin.Last) end
        if okL and type(last) == "table" and last.shown == true then
            out[#out + 1] = WB.PIN_SAYS .. ": shown."
        else
            local why = okL and type(last) == "table" and last.reason or "not looked at yet"
            out[#out + 1] = WB.PIN_SAYS .. ": not shown (" .. tostring(why) .. "); " .. WB.PIN_WHEN .. "."
        end
        return out
    end

    local function click(win)
        local provider = k.use(win.opens)
        local fn = type(provider) == "table" and provider[win.call] or nil
        if type(fn) ~= "function" then
            k.problems:add("windowButtons", win.key, "the " .. win.opens .. " cannot be opened from here yet")
            return
        end
        local ok, err = pcall(fn)
        if not ok then k.problems:add("windowButtons", win.key, tostring(err)) end
    end

    local function update(win)
        if not ctx then return end
        local on = ctx.settings:get(win.setting) == true
        local h = handles[win.key]
        reasons[win.key] = nil
        if not on then
            if h then h.show(false) end
            states[win.key] = "off"
            return
        end
        if h then
            h.show(true)
            states[win.key] = "shown"
            return
        end
        if ctx.client.inCombat() ~= false then
            states[win.key] = "waiting for combat to end"
            return
        end
        local make = ctx.client.windowButton
        local id = k.id or ns.id
        local why = WB.NO_READ
        h = nil
        if type(make) == "function" then
            for _, place in ipairs(WB.Places(win)) do
                local p = place.point
                h, why = make(win.frame, {
                    name = id.framePrefix .. "Button" .. win.frame,
                    text = id.title, tip = id.title .. ": " .. win.tip,
                    point = { p[1], p[2], p[3], p[4] },
                    inside = place.inside, strata = win.strata,
                })
                if type(h) == "table" or why ~= WB.NO_PLACE then break end
            end
        end
        if type(h) ~= "table" then
            states[win.key] = "not made"
            reasons[win.key] = type(why) == "string" and why or "no reason given"
            return
        end
        handles[win.key] = h
        h.onClick(function() click(win) end)
        h.show(true)
        states[win.key] = "shown"
    end

    local function updateAll()
        for _, win in ipairs(WB.WINDOWS) do update(win) end
    end

    -- Its window may not be there at login, or may only then be there to
    -- ask: a button not made is tried again when the window opens.
    local function retry(win)
        if states[win.key] == "not made" then update(win) end
    end

    if diag and type(diag.commands) == "table" then
        diag.commands[WB.WORD] = function()
            local id = k.id or ns.id
            local client = ctx and ctx.client or k.client
            if type(client) ~= "table" or type(client.print) ~= "function" then return end
            local lines = api.lines()
            for _, line in ipairs(api.surfaceLines()) do lines[#lines + 1] = line end
            for i = 1, #lines do client.print(id.title .. ": " .. lines[i]) end
        end
        if type(diag.help) == "table" then diag.help[WB.WORD] = WB.HELP end
    end

    k:Module({
        name = WB.NAME,
        needs = { "client", "store", "settings", "bus" },
        provides = { State = api.state },
        start = function(c)
            ctx = c
            for _, win in ipairs(WB.WINDOWS) do
                local row = c.settings:row(win.setting)
                local scope = row and row.scope or "account"
                local path = row and row.path or ("settings." .. win.setting)
                cancels[#cancels + 1] = c.store:watch(scope, path, function() update(win) end)
                c.bus:on(WB.NAME, win.retry, function() retry(win) end)
            end
            c.bus:on(WB.NAME, "PLAYER_REGEN_ENABLED", updateAll)
            updateAll()
        end,
        stop = function()
            for i = 1, #cancels do cancels[i]() end
            cancels = {}
            for _, h in pairs(handles) do h.show(false) end
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.windowButtons = WB.Declare(ns, ns.diag)
