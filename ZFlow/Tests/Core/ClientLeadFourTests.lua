-- Lead client4: client.worldMapFrame() and client.hideTooltip(prefix),
-- against hand-written stand-ins for the game's globals and the fake; and
-- the three places that use them or client.windowButton (the Banker
-- buttons, the Deals button, the card's tooltip hide). Made-up answers
-- only. Not tested in game.
local _, ns = ...

local function frame(t)
    local f = { name = t.name, parent = t.parent }
    function f:IsShown() return t.shown end
    function f:GetRight() return t.right end
    function f:GetTop() return t.top end
    function f:GetHeight() return t.height end
    function f:GetName() return self.name end
    function f:GetParent() return self.parent end
    return f
end

local function tipEnv(ownerName, parentName)
    local parent = nil
    if parentName then parent = frame({ name = parentName }) end
    local owner = frame({ name = ownerName, parent = parent })
    local tip = { shown = true }
    function tip:IsShown() return self.shown end
    function tip:GetOwner() return owner end
    function tip:Hide() self.shown = false end
    return { GameTooltip = tip }, tip
end

local tests = {}

tests["world map frame: its edges while shown, no panel on this client"] = function(t)
    local env = { WorldMapFrame = frame({ shown = true, right = 900, top = 700, height = 500 }) }
    local m = ns.make.client(env).worldMapFrame()
    t.eq(m.shown, true)
    t.eq(m.right, 900)
    t.eq(m.top, 700)
    t.eq(m.height, 500)
    t.eq(m.panel, nil, "the Classic-era map has no quest panel")
end

tests["world map frame: hidden says only that; absent or unsaid is nil"] = function(t)
    local env = { WorldMapFrame = frame({ shown = false, right = 900 }) }
    local m = ns.make.client(env).worldMapFrame()
    t.eq(m.shown, false)
    t.eq(m.right, nil, "no edges while hidden")
    t.eq(ns.make.client({}).worldMapFrame(), nil, "no WorldMapFrame")
    local bad = frame({ shown = true, right = 0 / 0 })
    bad.IsShown = function() error("no") end
    t.eq(ns.make.client({ WorldMapFrame = bad }).worldMapFrame(), nil, "IsShown fails")
    local odd = { WorldMapFrame = frame({ shown = true, right = 0 / 0, top = "x" }) }
    local o = ns.make.client(odd).worldMapFrame()
    t.eq(o.right, nil, "not a plain number")
    t.eq(o.top, nil)
end

tests["hide tooltip: hidden only when a Z-Flow frame (or its parent) owns it"] = function(t)
    local env, tip = tipEnv("ZFlowRouteListRow")
    t.eq(ns.make.client(env).hideTooltip("ZFlow"), true)
    t.eq(tip.shown, false)
    env = tipEnv(nil, "ZFlowStepCard")
    t.eq(ns.make.client(env).hideTooltip("ZFlow"), true, "an unnamed child of a named window")
    env, tip = tipEnv("BagnonFrame")
    t.eq(ns.make.client(env).hideTooltip("ZFlow"), false, "another addon's tooltip is left alone")
    t.eq(tip.shown, true)
    t.eq(ns.make.client({}).hideTooltip("ZFlow"), false, "no GameTooltip")
    t.eq(ns.make.client(env).hideTooltip(nil), false, "no prefix")
end

tests["fake: world map frame and tooltip hide as the real ones"] = function(t)
    local c = ns.make.fakeClient()
    t.eq(c.worldMapFrame(), nil)
    c.setWorldMapFrame({ shown = true, right = 10, top = 20, height = 30, panel = { shown = true, left = 5 } })
    local m = c.worldMapFrame()
    t.eq(m.right, 10)
    t.eq(m.panel.left, 5)
    c.setTooltipOwner("Other")
    t.eq(c.hideTooltip("ZFlow"), false)
    c.setTooltipOwner("ZFlowX")
    t.eq(c.hideTooltip("ZFlow"), true)
    t.eq(c.tooltipHides, 1)
end

local function booted(declare)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    local k = ns.Kernel({}, c)
    ns.Diag.Start(k)
    local api = declare(k, c)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return c, k, api
end

local function buttonOn(c, frameName)
    for _, h in ipairs(c.windowButtons) do
        if h.frame == frameName then return h end
    end
    return nil
end

tests["banker buttons: one on the bank frame, one above the backpack; each opens the window"] = function(t)
    local c, _, api = booted(function(k, c)
        c.setWindow("BankFrame", {})
        c.setWindow("ContainerFrame1", {})
        return ns.BankerWindow.Declare(k, ns.diag)
    end)
    local bank, bags = buttonOn(c, "BankFrame"), buttonOn(c, "ContainerFrame1")
    t.ok(bank ~= nil and bags ~= nil, "both made")
    t.eq(bank.shown, true)
    t.eq(bank.spec.name, ns.id.framePrefix .. "BankerBankButton")
    local before = api.shows()
    bags.click()
    t.eq(api.shows(), before + 1, "the bag button opens it")
    bank.click()
    t.eq(api.shows(), before + 2, "and the bank button")
end

tests["deals button: made once the auction frame exists, follows On, opens the window"] = function(t)
    local c, k, api = booted(function(k)
        ns.Trader.Declare(k, ns.diag)
        return ns.DealsPanel.Declare(k)
    end)
    t.eq(buttonOn(c, "AuctionFrame"), nil, "Blizzard_AuctionUI not loaded yet")
    c.setWindow("AuctionFrame", {})
    c.fire("ADDON_LOADED", "Blizzard_AuctionUI")
    local b = buttonOn(c, "AuctionFrame")
    t.ok(b ~= nil, "made on its ADDON_LOADED")
    t.eq(b.shown, true)
    b.click()
    local w = c.kitWindows()[ns.DealsPanel.ID]
    t.ok(w ~= nil and w.shown == true, "the Deals window opens")
    k.settings:set(ns.Trader.SETTING, true)
    api.follow()
    t.eq(b.shown, false, "the trader off: no button")
    t.eq(api.open(), false, "and nothing to open")
end

return tests
