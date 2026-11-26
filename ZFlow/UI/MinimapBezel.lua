local _, ns = ...

-- MinimapBezel (slice 6, §8.2): the thin-line border on the
-- minimap in place of the stock Blizzard border, with the choice
-- kept as a setting: nav.minimapBezel (account, OFF by default
-- since the lead's §913 ruling); on draws the line and hides the
-- stock border, off puts the stock border back. The border
-- itself is the client's (client.minimapBezel); this module
-- only follows the setting and hands it over, with the strip
-- colour out of the kit theme. The minimap's dots are the
-- minimap's own children and stay above the border in both modes.
--
--   BZ.Declare(k, diag) -> api   api.Refresh(), api.Applied()
-- Not tested in game.

local BZ = {}
ns.MinimapBezel = BZ

BZ.NAME = "minimapBezel"
BZ.SETTING = "nav.minimapBezel"
BZ.EVERY = 0.5     -- seconds between looks. A first guess.

-- The strip colour: the kit theme's edge colour, handed to the
-- client, which holds no colour of its own. nil when the theme
-- has no edge colour to give.
function BZ.Colour()
    local T = ns.KitTheme
    local col
    if type(T) == "table" and type(T.color) == "table" then col = T.color.edge end
    if type(col) ~= "table" then return nil end
    return { r = col[1], g = col[2], b = col[3], a = col[4] }
end

function BZ.Declare(k, diag)
    local api = {}
    local ctx, handle, applied

    function api.Applied() return applied end

    local function client()
        if ctx and ctx.client then return ctx.client end
        return k.client
    end

    function api.Refresh()
        if not ctx then return end
        local on = false
        local s = ctx.settings
        if type(s) == "table" and type(s.get) == "function" then
            local ok, v = pcall(s.get, s, BZ.SETTING)
            if ok and v == true then on = true end
        end
        if applied == on and handle then return end
        local c = client()
        if not handle then
            if type(c) ~= "table" or type(c.minimapBezel) ~= "function" then return end
            local ok, h = pcall(c.minimapBezel, BZ.Colour())
            if not ok or type(h) ~= "table" or type(h.show) ~= "function" then return end
            handle = h
        end
        local ok = pcall(handle.show, on)
        if ok then applied = on end
    end

    k:Setting({ key = BZ.SETTING, scope = "account", type = "bool", default = false,
        label = "Thin border on the minimap", group = "travel.map",
        help = "Draws a thin line around the minimap instead of the stock border. Off: the stock Blizzard border.",
        synonyms = { "minimap", "border", "bezel", "frame" } })

    k:Module({
        name = BZ.NAME,
        needs = { "client", "settings" },
        ticks = { { every = BZ.EVERY, when = "always", run = function() api.Refresh() end } },
        start = function(c)
            ctx = c
            api.Refresh()
        end,
        stop = function()
            if handle and applied == true then pcall(handle.show, false) end
            applied = nil
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.minimapBezel = BZ.Declare(ns, ns.diag)
