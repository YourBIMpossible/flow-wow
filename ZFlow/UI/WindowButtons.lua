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
-- No button is made on a window that is missing or protected, or while the
-- player is in combat; one wanted in combat is made when combat ends. A
-- button is made once and only shown or hidden after that.
--
--   WindowButtons.WINDOWS            the two windows: key, frame, setting row,
--                                    label, what a click opens, the button spec
--   WindowButtons.Declare(k) -> api  declares the module on kernel k
--     api.state() -> { worldMap = s, merchant = s }, s one of
--       "off", "shown", "waiting for combat to end", "not made"
--
-- Settings: "buttons.worldMap" and "buttons.merchant" (bool, account,
-- default off). The rows are the lead's to add; a missing row is off.
--
-- Reads (through the injected client):
--   client.windowButton(frameName, spec) -> h | nil    CLIENT NEED
--     spec = { name = global name, text = short label, tip = tooltip line,
--              point = { anchor, relative anchor, x, y } against the window }
--     nil when _G[frameName] is missing, frame:IsProtected() is true, or
--     InCombatLockdown() is true. h is a plain Button, a child of the window
--     (shown only while the window is): h.onClick(fn) fn() on a left click,
--     h.show(on). It never sets an attribute and is never secure.
--     Fake: c.setWindow(frameName, { protected = bool }) says a window exists.
--   client.inCombat()     true / false / nil (nil counts as in combat)
--   PLAYER_REGEN_ENABLED  combat ended
local _, ns = ...

local WB = ns.WindowButtons or {}
ns.WindowButtons = WB

WB.NAME = "windowButtons"

-- The button points are first guesses, not seen in game. The button text
-- and the start of its tooltip are the addon's title from the identity
-- (Core/Identity.lua is the only file that may hold it).
WB.WINDOWS = {
    {
        key = "worldMap", frame = "WorldMapFrame", setting = "buttons.worldMap",
        label = "Button on the world map",
        opens = "arrow", call = "OpenMenu",
        tip = "open the arrow menu",
        point = { "TOPRIGHT", "TOPRIGHT", -60, -30 },
    },
    {
        key = "merchant", frame = "MerchantFrame", setting = "buttons.merchant",
        label = "Button on the merchant window",
        opens = "sellList", call = "Show",
        tip = "show the sell list",
        point = { "TOPRIGHT", "TOPRIGHT", -40, -40 },
    },
}

function WB.Declare(k)
    local api = {}
    local handles, states = {}, {}
    local ctx
    local cancels = {}
    for _, win in ipairs(WB.WINDOWS) do states[win.key] = "off" end

    function api.state()
        local out = {}
        for key, s in pairs(states) do out[key] = s end
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
        h = type(make) == "function" and make(win.frame, {
            name = id.framePrefix .. "Button" .. win.frame,
            text = id.title, tip = id.title .. ": " .. win.tip,
            point = { win.point[1], win.point[2], win.point[3], win.point[4] },
        }) or nil
        if not h then
            states[win.key] = "not made"
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
ns.windowButtons = WB.Declare(ns)
