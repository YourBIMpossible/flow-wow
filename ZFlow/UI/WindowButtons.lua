-- Window buttons (U-E, S22): one Z-Flow button on the world map and one on
-- the merchant window. Both are OFF by default, and stay off until the
-- owner's per-window checks (WoW\from-zen\U-C-game-window-buttons-note.md)
-- are on record.
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
-- default off). The rows are the lead's to add; a missing row is off.
--
-- Reads (through the injected client):
--   client.windowButton(frameName, spec) -> h | nil    CLIENT NEED
--     spec = { name = global name, text = short label, tip = tooltip line,
--              point = { anchor, relative anchor, x, y } against the window }
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

-- The button points are first guesses, not seen in game. The button text
-- and the start of its tooltip are the addon's title from the identity
-- (Core/Identity.lua is the only file that may hold it).
WB.WINDOWS = {
    {
        key = "worldMap", frame = "WorldMapFrame", setting = "buttons.worldMap",
        label = "Button on the world map", says = "world map",
        retry = "PLAYER_ENTERING_WORLD",
        opens = "arrow", call = "OpenMenu",
        tip = "open the arrow menu",
        point = { "TOPRIGHT", "TOPRIGHT", -60, -30 },
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
            out[#out + 1] = line .. "."
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
            h, why = make(win.frame, {
                name = id.framePrefix .. "Button" .. win.frame,
                text = id.title, tip = id.title .. ": " .. win.tip,
                point = { win.point[1], win.point[2], win.point[3], win.point[4] },
            })
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
