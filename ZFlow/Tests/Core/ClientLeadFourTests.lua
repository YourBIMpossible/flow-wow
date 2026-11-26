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

local function bankerAndButtons(k, c)
    c.setWindow("BankFrame", {})
    c.setWindow("ContainerFrame1", {})
    ns.UIRows.Declare(k)
    local api = ns.BankerWindow.Declare(k, ns.diag)
    ns.WindowButtons.Declare(k)
    return api
end

tests["banker buttons: WindowButtons rows, each with its own setting, each opens its tab"] = function(t)
    local rows = {}
    for _, win in ipairs(ns.WindowButtons.WINDOWS) do rows[win.key] = win end
    t.eq(rows.banker.frame, "BankFrame")
    t.eq(rows.banker.setting, "buttons.banker")
    t.eq(rows.banker.args, { ns.BankerWindow.TAB_BANK }, "the bank one opens on To bank")
    t.eq(rows.bags.frame, "ContainerFrame1")
    t.eq(rows.bags.setting, "buttons.bags")
    t.eq(rows.bags.args, { ns.BankerWindow.TAB_IN }, "the bag one opens on In your bank")
    t.eq(rows.bank.text, "Bank list", "the Bank list row is unchanged")
    t.eq(rows.bank.point, { "TOPRIGHT", "TOPRIGHT", -40, -40 })
    t.ok(rows.banker.point[4] <= rows.bank.point[4] - 24, "Banker stands a button lower than Bank list")
    local c, k, api = booted(bankerAndButtons)
    local bank, bags
    for _, h in ipairs(c.windowButtons) do
        if h.spec.name == ns.id.framePrefix .. "BankerBankButton" then bank = h end
        if h.spec.name == ns.id.framePrefix .. "BankerBagButton" then bags = h end
    end
    t.ok(bank ~= nil and bags ~= nil, "both made, on by default")
    t.eq(bank.frame, "BankFrame")
    t.eq(bags.frame, "ContainerFrame1")
    t.eq(bank.shown, true)
    local before = api.shows()
    bags.click()
    t.eq(api.shows(), before + 1, "the bag button opens the window")
    bank.click()
    t.eq(api.shows(), before + 2, "and the bank button")
    k.settings:set("buttons.banker", false)
    t.eq(bank.shown, false, "its own setting hides the Banker button")
    t.eq(bags.shown, true, "and leaves the bag one")
end

tests["banker buttons: refused in a fight, made when the fight ends"] = function(t)
    local c = booted(function(k, cl)
        cl.setCombat(true)
        return bankerAndButtons(k, cl)
    end)
    for _, h in ipairs(c.windowButtons) do
        t.ok(h.spec.name ~= ns.id.framePrefix .. "BankerBankButton", "none in a fight")
    end
    c.setCombat(false)
    c.fire("PLAYER_REGEN_ENABLED")
    local made = false
    for _, h in ipairs(c.windowButtons) do
        if h.spec.name == ns.id.framePrefix .. "BankerBankButton" then made = true end
    end
    t.ok(made, "made once the fight is over")
end

tests["deals button: a WindowButtons row, made once the auction frame exists, follows the trader"] = function(t)
    local c, k, api = booted(function(k)
        ns.UIRows.Declare(k)
        ns.Trader.Declare(k, ns.diag)
        local dp = ns.DealsPanel.Declare(k)
        ns.WindowButtons.Declare(k)
        return dp
    end)
    t.eq(buttonOn(c, "AuctionFrame"), nil, "Blizzard_AuctionUI not loaded yet")
    c.setWindow("AuctionFrame", {})
    c.fire("ADDON_LOADED", "Blizzard_AuctionUI")
    local b = buttonOn(c, "AuctionFrame")
    t.ok(b ~= nil, "made on its ADDON_LOADED")
    t.eq(b.spec.name, ns.id.framePrefix .. "DealsButton")
    t.eq(b.shown, true)
    b.click()
    local w = c.kitWindows()[ns.DealsPanel.ID]
    t.ok(w ~= nil and w.shown == true, "the Deals window opens")
    k.settings:set(ns.Trader.SETTING, true)
    t.eq(b.shown, false, "the trader off: no button")
    t.eq(api.open(), false, "and nothing to open")
    k.settings:set(ns.Trader.SETTING, false)
    t.eq(b.shown, true, "the trader on again: the button is back")
    k.settings:set("buttons.deals", false)
    t.eq(b.shown, false, "its own setting hides it")
end

tests["buttons word: one line says what worldMapFrame() answers"] = function(t)
    local WB = ns.WindowButtons
    t.eq(WB.MapLine(nil), "world map frame: not read.")
    local c = ns.make.fakeClient()
    t.eq(WB.MapLine(c), "world map frame: not there.")
    c.setWorldMapFrame({ shown = true, right = 900, top = 700, height = 500 })
    t.eq(WB.MapLine(c), "world map frame: open, right 900, top 700, height 500, no quest panel.")
    c.setWorldMapFrame({ shown = false, panel = { shown = true } })
    t.eq(WB.MapLine(c), "world map frame: closed, quest panel open.")
end

-- CHANGES-2: opening the step card hides a tooltip that one of this
-- add-on's frames owns (the real client's hideTooltip over a fake
-- GameTooltip), and leaves another add-on's tooltip shown.
local function cardWithTip(ownerName)
    local env, tip = tipEnv(ownerName)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setScreen(1920, 1080)
    c.setQuestLog({})
    c.hideTooltip = ns.make.client(env).hideTooltip
    local k = ns.Kernel({}, c)
    ns.Diag.Start(k)
    local card = ns.StepCard.Declare(k, ns.diag)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return card, tip
end

local function cardStep()
    return { label = "Kill Gnolls", title = "Wanted: Gnolls", objective = "Gnoll Paw: 2/8",
             quest = 176, kind = "quest", place = { map = 1429, x = 0.4, y = 0.6 } }
end

tests["step card: Toggle hides a tooltip owned by one of this add-on's frames"] = function(t)
    local card, tip = cardWithTip(ns.id.framePrefix .. "RouteListRow")
    t.eq(tip.shown, true)
    t.ok(card.Toggle(cardStep(), { index = 1 }, nil), "the card opens")
    t.eq(tip.shown, false, "the tooltip under it is hidden")
end

tests["step card: Toggle leaves another add-on's tooltip shown"] = function(t)
    local card, tip = cardWithTip("BagnonFrame")
    t.ok(card.Toggle(cardStep(), { index = 1 }, nil), "the card opens")
    t.eq(tip.shown, true, "another add-on's tooltip stays")
end

return tests