local _, ns = ...
-- F-20 (lead sections 788, 790): "Tooltips where WoW shows them", as
-- Flow's switch (Modules/Settings.lua:743; Core.lua:317-318
-- ns.TipsAtGameSpot, :335-340 ns.Tip, which calls
-- GameTooltip_SetDefaultAnchor when it is on). On by default, as Flow
-- (section 563): this add-on's tooltips then show where the game shows its
-- own (the corner the player or another add-on chose), not beside the
-- frame that opened them. Off: beside it, as before.
--
-- Every tooltip is placed by Core/Client.lua (its SetOwner calls), so the
-- answer is handed to the client: client.setTipSpot(fn), a CLIENT NEED.
-- Each SetOwner asks fn(anchor) and, on TS.GAME, calls
-- GameTooltip_SetDefaultAnchor(tip, owner) instead of SetOwner(owner,
-- anchor). A tooltip placed by hand (ANCHOR_NONE, then SetPoint) keeps its
-- place either way.
--
--   TS.Where(on, anchor) -> TS.GAME | anchor   (pure; on nil = the default)
--   TS.Declare(k) -> api   api.Where(anchor)
-- Not tested in game.
local TS = {}
ns.TipSpot = TS

TS.NAME = "tipSpot"
TS.SETTING = "general.tipsAtGameSpot"
TS.GAME = "GAME"
TS.DEFAULT = true
TS.LABEL = "Tooltips where WoW shows them"
TS.HELP = "On: this add-on's tooltips show where the game shows its own. "
    .. "Off: beside the button or line you point at."
TS.BY_HAND = { ANCHOR_NONE = true, ANCHOR_PRESERVE = true }

function TS.Where(on, anchor)
    if TS.BY_HAND[anchor] then return anchor end
    if on == nil then on = TS.DEFAULT end
    if on then return TS.GAME end
    return anchor
end

function TS.Declare(k)
    local api = {}
    local ctx

    local function on()
        if not ctx or type(ctx.settings) ~= "table" then return nil end
        local ok, v = pcall(ctx.settings.get, ctx.settings, TS.SETTING)
        if ok and type(v) == "boolean" then return v end
        return nil
    end

    function api.Where(anchor) return TS.Where(on(), anchor) end

    k:Setting({ key = TS.SETTING, scope = "account", type = "bool", default = TS.DEFAULT,
        group = "general.windows", synonyms = { "tooltip", "tooltips", "tips", "anchor", "corner" },
        label = TS.LABEL, help = TS.HELP })

    k:Module({
        name = TS.NAME,
        needs = { "client", "settings" },
        provides = { Where = api.Where },
        start = function(c)
            ctx = c
            local client = c.client
            if type(client) == "table" and type(client.setTipSpot) == "function" then
                pcall(client.setTipSpot, function(anchor) return api.Where(anchor) end)
            end
        end,
        stop = function() ctx = nil end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.tipSpot = TS.Declare(ns)
