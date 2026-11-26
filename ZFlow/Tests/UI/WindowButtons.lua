local _, ns = ...

-- Tests for ZFlow/UI/WindowButtons.lua (U-E, S22): one Z-Flow button on the
-- world map and one on the merchant window, both off by default. A button
-- only shows a Z-Flow panel: the world map's shows the arrow menu, the
-- merchant's shows the sell list. Fake client; not tested in game.
--
-- The window read is a CLIENT NEED: client.windowButton(frameName, spec)
-- answers a handle or nil (the window missing, protected, or the player in
-- combat), and the fake's setWindow(frameName, { protected = bool }) says
-- which windows exist. Until the fake has them, these tests put them on the
-- fake in the same shape. The panels are reached through two PROVIDER
-- NEEDs: the "arrow" module's OpenMenu() and the "sellList" module's Show();
-- fake modules stand in for both here.

local W = ns.WindowButtons
local tests = {}

local function windows(c)
    c.windowButtons = c.windowButtons or {}
    if type(c.windowButton) == "function" and type(c.setWindow) == "function" then return end
    local wins = {}
    function c.setWindow(name, w) wins[name] = w or {} end
    function c.windowButton(frameName, spec)
        local w = wins[frameName]
        if not w or w.protected or c.inCombat() ~= false then return nil end
        local h = { frame = frameName, spec = spec, shown = false }
        local fn
        function h.onClick(f) fn = f end
        function h.show(on) h.shown = on and true or false end
        function h.click() if fn then fn() end end
        c.windowButtons[#c.windowButtons + 1] = h
        return h
    end
end

-- opts: rows (false: none declared), on = { worldMap = bool, merchant = bool }
-- (saved before login), windows = { [frame] = { protected } } (default both,
-- unprotected), combat (in combat at login), providers (false: none),
-- id (an identity for the kernel; default ns.id).
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    local account = {}
    if opts.on then account.settings = { buttons = { worldMap = opts.on.worldMap, merchant = opts.on.merchant } } end
    c.setSaved(ns.id.accountDB, account)
    windows(c)
    local wins = opts.windows or { WorldMapFrame = {}, MerchantFrame = {} }
    for name, w in pairs(wins) do c.setWindow(name, w) end
    if opts.combat then c.setCombat(true) end
    local k = ns.Kernel({}, c, opts.id)
    ns.Diag.Start(k)
    if opts.rows ~= false then
        for _, win in ipairs(W.WINDOWS) do
            k:Setting({ key = win.setting, scope = "account", type = "bool", default = false, label = win.label })
        end
    end
    local opened = { menu = 0, sell = 0 }
    if opts.providers ~= false then
        k:Module({ name = "arrow", provides = { OpenMenu = function() opened.menu = opened.menu + 1 end } })
        k:Module({ name = "sellList", provides = { Show = function() opened.sell = opened.sell + 1 end } })
    end
    local api = W.Declare(k)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c, api, opened
end

local function buttonOn(c, frame)
    for _, h in ipairs(c.windowButtons) do
        if h.frame == frame then return h end
    end
    return nil
end

tests["window buttons: eight rows, each with its own setting"] = function(t)
    t.eq(#W.WINDOWS, 8)
    local seen = {}
    for _, win in ipairs(W.WINDOWS) do seen[win.key] = win.frame .. " " .. win.setting end
    t.eq(seen, { worldMap = "WorldMapFrame buttons.worldMap", merchant = "MerchantFrame buttons.merchant",
        profession = "TradeSkillFrame buttons.profession", bank = "BankFrame buttons.bank",
        banker = "BankFrame buttons.banker", bags = "ContainerFrame1 buttons.bags",
        deals = "AuctionFrame buttons.deals", talents = "PlayerSpellsFrame buttons.talents" })
end

tests["window buttons: off by default - no button is made"] = function(t)
    local k, c, api = start()
    t.eq((k:ModuleState(W.NAME)), "started")
    t.eq(#c.windowButtons, 0, "no button")
    t.eq(api.state(), { worldMap = "off", merchant = "off", profession = "off", bank = "off",
        banker = "off", bags = "off", deals = "off", talents = "off" })
    t.ok(type(ns.windowButtons) == "table", "the addon's own is declared")
end

tests["window buttons: a missing row is off too"] = function(t)
    local _, c = start({ rows = false, on = { worldMap = true, merchant = true } })
    t.eq(#c.windowButtons, 0, "no row, no button")
end

tests["window buttons: the world map button shows the arrow menu, and only that"] = function(t)
    local _, c, api, opened = start({ on = { worldMap = true } })
    local h = buttonOn(c, "WorldMapFrame")
    t.ok(h ~= nil, "a button on the world map")
    t.eq(h.shown, true)
    t.eq(buttonOn(c, "MerchantFrame"), nil, "none on the merchant window")
    h.click()
    t.eq(opened, { menu = 1, sell = 0 }, "the arrow menu, once")
    t.eq(api.state().worldMap, "shown")
end

tests["window buttons: the merchant button shows the sell list, and only that"] = function(t)
    local _, c, _, opened = start({ on = { merchant = true } })
    local h = buttonOn(c, "MerchantFrame")
    t.ok(h ~= nil, "a button on the merchant window")
    h.click()
    t.eq(opened, { menu = 0, sell = 1 }, "the sell list, once")
end

-- Section 134: the rule of section 132 is taken back. A missing window
-- and a protected one both get none, each with its own reason.
tests["window buttons: a missing window and a protected one get no button, each with its reason"] = function(t)
    local _, c, api = start({ on = { worldMap = true, merchant = true },
        windows = { MerchantFrame = { protected = true } } })
    t.eq(#c.windowButtons, 0, "none")
    t.eq(api.state(), { worldMap = "not made", merchant = "not made", profession = "off", bank = "off",
        banker = "off", bags = "off", deals = "off", talents = "off" })
    t.eq(api.reasons(), { worldMap = "no window", merchant = "its window is protected" })
end

tests["window buttons: a window that will not say whether it is protected gets none, and says so"] = function(t)
    local _, c, api = start({ on = { merchant = true },
        windows = { MerchantFrame = { protected = "unsaid" } } })
    t.eq(#c.windowButtons, 0, "none")
    t.eq(api.reasons().merchant, "its window will not say whether it is protected")
end

tests["window buttons: a protected window is asked again when it opens"] = function(t)
    local _, c, api = start({ on = { merchant = true },
        windows = { MerchantFrame = { protected = true } } })
    c.fire("MERCHANT_SHOW")
    t.eq(#c.windowButtons, 0, "still protected: still none")
    t.eq(api.reasons().merchant, "its window is protected")
    c.setWindow("MerchantFrame", { shown = true })
    c.fire("MERCHANT_SHOW")
    t.ok(buttonOn(c, "MerchantFrame") ~= nil, "made once the window is not protected")
    t.eq(api.state().merchant, "shown")
end

tests["window buttons: a window that is not there at login gets its button when it opens"] = function(t)
    local _, c, api = start({ on = { merchant = true }, windows = {} })
    t.eq(api.state().merchant, "not made")
    t.eq(api.reasons().merchant, "no window")
    c.setWindow("MerchantFrame", {})
    c.fire("MERCHANT_SHOW")
    local h = buttonOn(c, "MerchantFrame")
    t.ok(h ~= nil, "made when the window opened")
    t.eq(h and h.shown, true)
    t.eq(api.state().merchant, "shown")
    t.eq(api.reasons().merchant, nil, "no reason is left")
    c.fire("MERCHANT_SHOW")
    t.eq(#c.windowButtons, 1, "not a second one")
end

tests["window buttons: the world map button is tried again on entering the world"] = function(t)
    local _, c, api = start({ on = { worldMap = true }, windows = {} })
    t.eq(api.state().worldMap, "not made")
    c.setWindow("WorldMapFrame", {})
    c.fire("PLAYER_ENTERING_WORLD")
    t.ok(buttonOn(c, "WorldMapFrame") ~= nil, "made")
    t.eq(api.state().worldMap, "shown")
end

tests["window buttons: a button that is off is not made when its window opens"] = function(t)
    local _, c, api = start({ windows = {} })
    c.setWindow("MerchantFrame", {})
    c.fire("MERCHANT_SHOW")
    t.eq(#c.windowButtons, 0)
    t.eq(api.state().merchant, "off")
end

tests["window buttons: a window that opens in combat waits for combat to end"] = function(t)
    local _, c, api = start({ on = { merchant = true }, windows = {} })
    c.setWindow("MerchantFrame", {})
    c.setCombat(true)
    c.fire("MERCHANT_SHOW")
    t.eq(#c.windowButtons, 0, "none in combat")
    t.eq(api.state().merchant, "waiting for combat to end")
    c.setCombat(false)
    t.ok(buttonOn(c, "MerchantFrame") ~= nil, "made after combat")
end

tests["window buttons: the lines say each state, and why one was not made"] = function(t)
    local _, _, api = start({ on = { worldMap = true, merchant = true },
        windows = { MerchantFrame = { protected = true } } })
    t.eq(api.lines(), {
        "button on the world map: not made (no window); window not there.",
        "button on the merchant window: not made (its window is protected); window there, protected.",
        "button on the profession window: off; window not there.",
        "button on the bank window: off; window not there.",
        "button on the bank window (Banker): off; window not there.",
        "button on the backpack: off; window not there.",
        "button on the auction house: off; window not there.",
        "button on the talent window: off; window not there.",
    })
    local _, _, off = start()
    t.eq(off.lines(), {
        "button on the world map: off; window there, not protected.",
        "button on the merchant window: off; window there, not protected.",
        "button on the profession window: off; window not there.",
        "button on the bank window: off; window not there.",
        "button on the bank window (Banker): off; window not there.",
        "button on the backpack: off; window not there.",
        "button on the auction house: off; window not there.",
        "button on the talent window: off; window not there.",
    })
end

tests["window buttons: the lines say what the window is, and whether a shown button can be seen"] = function(t)
    local _, c, api = start({ on = { merchant = true },
        windows = { WorldMapFrame = { protected = "unsaid", shown = false }, MerchantFrame = { shown = true } } })
    t.eq(api.lines(), {
        "button on the world map: off; window there, closed, will not say whether it is protected.",
        "button on the merchant window: shown; window there, open, not protected; button can be seen.",
        "button on the profession window: off; window not there.",
        "button on the bank window: off; window not there.",
        "button on the bank window (Banker): off; window not there.",
        "button on the backpack: off; window not there.",
        "button on the auction house: off; window not there.",
        "button on the talent window: off; window not there.",
    })
    c.setWindow("MerchantFrame", { shown = false })
    t.eq(api.lines()[2],
        "button on the merchant window: shown; window there, closed, not protected; button cannot be seen.")
    c.windowState = nil
    t.eq(api.lines()[1], "button on the world map: off; window not read.")
end

tests["window buttons: the word prints the lines"] = function(t)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { settings = { buttons = { merchant = true } } })
    local k = ns.Kernel({}, c)
    local diag = ns.Diag.Start(k)
    for _, win in ipairs(W.WINDOWS) do
        k:Setting({ key = win.setting, scope = "account", type = "bool", default = false, label = win.label })
    end
    local api = W.Declare(k, diag)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    t.eq(type(diag.commands[W.WORD]), "function")
    t.eq(diag.help[W.WORD], W.HELP)
    local n = #c.printed
    diag.commands[W.WORD]("")
    local lines = api.lines()
    for _, line in ipairs(api.surfaceLines()) do lines[#lines + 1] = line end
    lines[#lines + 1] = W.MapLine(c)
    t.eq(#c.printed, n + #lines, "the buttons' lines, then the other surfaces' (lead section 296)")
    t.eq(c.printed[n + 2], ns.id.title .. ": button on the merchant window: not made (no window); window not there.")
    for i = 1, #lines do
        t.ok(not lines[i]:find("Flow", 1, true), "no name spelled out: " .. lines[i])
    end
end

tests["window buttons: none is made in combat; it is made when combat ends"] = function(t)
    local _, c, api = start({ on = { worldMap = true }, combat = true })
    t.eq(#c.windowButtons, 0, "none in combat")
    t.eq(api.state().worldMap, "waiting for combat to end")
    c.setCombat(false)
    t.ok(buttonOn(c, "WorldMapFrame") ~= nil, "made after combat")
    t.eq(api.state().worldMap, "shown")
end

tests["window buttons: turning a row on makes the button; off hides it; on again reuses it"] = function(t)
    local k, c, api = start()
    k.settings:set("buttons.merchant", true)
    local h = buttonOn(c, "MerchantFrame")
    t.ok(h ~= nil, "made when turned on")
    t.eq(h.shown, true)
    k.settings:set("buttons.merchant", false)
    t.eq(h.shown, false, "hidden when turned off")
    t.eq(api.state().merchant, "off")
    k.settings:set("buttons.merchant", true)
    t.eq(h.shown, true, "shown again")
    t.eq(#c.windowButtons, 1, "the same button, not a second one")
end

tests["window buttons: with no panel to open, a click does nothing and is recorded"] = function(t)
    local k, c = start({ on = { worldMap = true }, providers = false })
    local h = buttonOn(c, "WorldMapFrame")
    local before = #k.problems:list()
    h.click()
    t.ok(#k.problems:list() > before, "recorded as a problem")
end

tests["window buttons: a client without the window read makes nothing and does not fail"] = function(t)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { settings = { buttons = { worldMap = true } } })
    local k = ns.Kernel({}, c)
    ns.Diag.Start(k)
    k:Setting({ key = "buttons.worldMap", scope = "account", type = "bool", default = false, label = "x" })
    local api = W.Declare(k)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    t.eq((k:ModuleState(W.NAME)), "started", "still started")
    t.eq(api.state().worldMap, "not made")
    t.eq(api.reasons().worldMap, c.windowButton and "no window" or W.NO_READ)
end

tests["window buttons: look only - plain buttons, no secure fields, no acting functions"] = function(t)
    local _, c = start({ on = { worldMap = true, merchant = true } })
    for _, h in ipairs(c.windowButtons) do
        for field in pairs(h.spec) do
            local f = tostring(field):lower()
            t.ok(not (f:find("secure") or f:find("macro") or f:find("spell") or f:find("attribute") or f:find("action")),
                "no acting field: " .. f)
        end
    end
    for name in pairs(W) do
        local n = tostring(name):lower()
        t.ok(not (n:find("sell") or n:find("buy") or n:find("cast") or n:find("secure")), "no acting function: " .. n)
    end
end

-- Section 142: the owner saw the world map button under the quest log
-- header at the top right of the map window. It must not be asked for
-- against the top of the window again. Lead section 293: it then sat under
-- the quest log "Q" toggle at the bottom right of the map. It now stands
-- on the toggle itself, just above it and flush with its right edge, as
-- legacy Flow's map button did (Modules/Nav/MapOverlay.lua:1176-1186);
-- only when the client has no toggle does it go to the map's corner.
local ABOVE_TOGGLE = { "BOTTOMRIGHT", "TOPRIGHT", 0, 4 }
local MAP_CORNER = { "BOTTOMRIGHT", "BOTTOMRIGHT", -44, 4 }

tests["window buttons: the world map button stands just above the quest log toggle, never over it"] = function(t)
    local _, c, api = start({ on = { worldMap = true, merchant = true },
        windows = { WorldMapFrame = { shown = true, parts = { "SidePanelToggle", "ScrollContainer" } },
            MerchantFrame = { shown = true } } })
    local map = buttonOn(c, "WorldMapFrame")
    t.ok(map ~= nil, "made")
    t.eq(map.spec.inside, { "SidePanelToggle" }, "against the toggle, a part of the window")
    t.eq(map.spec.point, ABOVE_TOGGLE, "its bottom on the toggle's top: above it, not on it")
    t.eq(map.spec.strata, "HIGH")
    t.eq(map.placedOn, "SidePanelToggle")
    t.eq(#c.windowButtons, 2, "one button on the map, one on the merchant: no second try left behind")
    t.eq(api.lines()[1],
        "button on the world map: shown; window there, open, not protected; button can be seen; placed above the quest log toggle.")
end

tests["window buttons: with no quest log toggle, the world map button goes to the map's corner"] = function(t)
    local _, c, api = start({ on = { worldMap = true },
        windows = { WorldMapFrame = { shown = true, parts = { "ScrollContainer" } }, MerchantFrame = {} } })
    local map = buttonOn(c, "WorldMapFrame")
    t.ok(map ~= nil, "made")
    t.eq(map.spec.inside, { "ScrollContainer" })
    t.eq(map.spec.point, MAP_CORNER)
    t.eq(map.placedOn, "ScrollContainer")
    t.eq(api.lines()[1],
        "button on the world map: shown; window there, open, not protected; button can be seen; placed on the map itself.")
end

tests["window buttons: the merchant button stays where the owner saw it"] = function(t)
    local _, c, api = start({ on = { worldMap = true, merchant = true },
        windows = { WorldMapFrame = { shown = true }, MerchantFrame = { shown = true } } })
    local shop = buttonOn(c, "MerchantFrame")
    t.eq(shop.spec.point, { "TOPRIGHT", "TOPRIGHT", -40, -40 })
    t.eq(shop.spec.inside, nil, "against the window itself")
    t.eq(shop.spec.strata, nil)
    t.eq(api.lines()[2],
        "button on the merchant window: shown; window there, open, not protected; button can be seen.")
end

tests["window buttons: a map window with no map part gets no button, and the line says why"] = function(t)
    local _, c, api = start({ on = { worldMap = true },
        windows = { WorldMapFrame = { parts = {} }, MerchantFrame = {} } })
    t.eq(buttonOn(c, "WorldMapFrame"), nil, "no guess at another place")
    t.eq(api.state().worldMap, "not made")
    t.eq(api.lines()[1],
        "button on the world map: not made (its place inside the window was not found); window there, not protected.")
    c.setWindow("WorldMapFrame", { parts = { "ScrollContainer" } })
    c.fire("PLAYER_ENTERING_WORLD")
    t.eq(api.state().worldMap, "shown", "asked again, and made once the part is there")
end

tests["window buttons: the button's text and tooltip name the addon from the identity"] = function(t)
    local id = {}
    for key, v in pairs(ns.id) do id[key] = v end
    id.title = "Test-Addon"
    local _, c = start({ on = { worldMap = true, merchant = true }, id = id })
    t.eq(#c.windowButtons, 2)
    for _, h in ipairs(c.windowButtons) do
        t.eq(h.spec.text, "Test-Addon", "the title from the identity")
        t.ok(h.spec.tip:find("Test-Addon", 1, true) == 1, "the tooltip starts with it")
        t.ok(not h.spec.tip:find(ns.id.title, 1, true), "nothing written in")
    end
    for _, win in ipairs(W.WINDOWS) do
        for field, v in pairs(win) do
            if type(v) == "string" then
                t.ok(not v:find(ns.id.title, 1, true) and not v:find(ns.id.slash, 1, true), "no identity in " .. field)
            end
        end
    end
end

return tests
