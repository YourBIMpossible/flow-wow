-- The setting rows of the welcome and the window buttons (UI/Rows.lua, F9):
-- declared once, with their defaults, and read by UI/Intro.lua and
-- UI/WindowButtons.lua. Fake client; not tested in game.
local _, ns = ...

local R = ns.UIRows

local function kernel(saved)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, saved and saved.account or {})
    if saved and saved.char then c.setSaved(ns.id.charDB, saved.char) end
    local k = ns.Kernel({}, c)
    local diag = ns.Diag.Start(k)
    return k, c, diag
end

local function login(k, c)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
end

local function introPanel(c)
    for _, p in ipairs(c.panels) do
        if type(p.spec) == "table" and p.spec.name == ns.id.framePrefix .. "Intro" then return p end
    end
    return nil
end

-- The welcome on the screen: the kit window (UI/Intro.lua draws it with
-- the kit), or the plain panel when the kit window is refused.
local function introShown(c)
    local w = type(c.kitWindows) == "function" and c.kitWindows().Intro
    if type(w) == "table" and w.shown == true then return true end
    local p = introPanel(c)
    return p ~= nil and p.shown == true
end

return {
    ["rows: every row has a label, a help line and the group"] = function(t)
        local k = kernel()
        t.eq(R.Declare(k), 9)
        for _, key in ipairs({ "ui.intro", "buttons.worldMap", "buttons.merchant", "buttons.profession",
            "buttons.bank", "buttons.banker", "buttons.bags", "buttons.deals" }) do
            local row = k.settings:row(key)
            t.ok(row ~= nil, key)
            if row then
                t.eq(row.type, "bool", key)
                t.eq(row.group, R.GROUP, key)
                t.ok(type(row.label) == "string" and row.label ~= "", key .. " label")
                t.ok(type(row.help) == "string" and row.help ~= "", key .. " help")
            end
        end
    end,

    -- Both window buttons are on unless the player turned one off: the
    -- world map's by default-on, the merchant's by lead section 294 item 3.
    ["rows: the welcome is on for this character; for the account both window buttons are on"] = function(t)
        local k, c = kernel()
        R.Declare(k)
        t.eq(k.settings:row("ui.intro").scope, "char")
        t.eq(k.settings:row("ui.intro").default, true)
        t.eq(k.settings:row("buttons.worldMap").scope, "account")
        t.eq(k.settings:row("buttons.worldMap").default, true)
        t.eq(k.settings:row("buttons.merchant").scope, "account")
        t.eq(k.settings:row("buttons.merchant").default, true)
        login(k, c)
        t.eq(k.settings:get("ui.intro"), true)
        t.eq(k.settings:get("buttons.worldMap"), true)
        t.eq(k.settings:get("buttons.merchant"), true)
    end,

    -- A saved "off" still means off: the default only fills what was never
    -- chosen. No button is made, on a merchant window that is there.
    ["rows: a merchant button the player turned off stays off"] = function(t)
        local k, c = kernel({ account = { settings = { buttons = { merchant = false } } } })
        R.Declare(k)
        c.setWindow("MerchantFrame", {})
        k:Module({ name = "sellList", provides = { Show = function() end } })
        local buttons = ns.WindowButtons.Declare(k)
        login(k, c)
        t.eq(k.settings:get("buttons.merchant"), false, "the saved choice, not the default")
        t.eq(#c.windowButtons, 0, "no button is made")
        t.eq(buttons.state().merchant, "off")
    end,

    -- At a default profile both windows have their button. Before the
    -- merchant flip only the world map's was made.
    ["rows: at a default profile both window buttons are made"] = function(t)
        local k, c = kernel()
        R.Declare(k)
        c.setWindow("WorldMapFrame", {})
        c.setWindow("MerchantFrame", {})
        local shown = 0
        k:Module({ name = "arrow", provides = { OpenMenu = function() end } })
        k:Module({ name = "sellList", provides = { Show = function() shown = shown + 1 end } })
        local buttons = ns.WindowButtons.Declare(k)
        login(k, c)
        t.eq(#c.windowButtons, 2, "two buttons")
        local merchant = nil
        for _, b in ipairs(c.windowButtons) do
            if b.frame == "MerchantFrame" then merchant = b end
        end
        t.eq(merchant and merchant.shown, true, "the merchant window has its button")
        t.eq(buttons.state(), { worldMap = "shown", merchant = "shown", profession = "not made", bank = "not made",
            banker = "not made", bags = "not made", deals = "not made", talents = "not made" },
            "the two windows not there yet wait for theirs")
        if merchant then merchant.click() end
        t.eq(shown, 1, "the click shows the sell list")
    end,

    ["rows: they are the keys the welcome and the buttons read"] = function(t)
        t.eq(ns.Intro.SETTING, "ui.intro")
        local keys = {}
        for _, win in ipairs(ns.WindowButtons.WINDOWS) do keys[win.setting] = true end
        t.eq(keys, { ["buttons.worldMap"] = true, ["buttons.merchant"] = true, ["buttons.profession"] = true,
            ["buttons.bank"] = true, ["buttons.banker"] = true, ["buttons.bags"] = true,
            ["buttons.deals"] = true, ["buttons.talents"] = true })
    end,

    ["rows: a second declaration is refused"] = function(t)
        local k = kernel()
        t.eq(R.Declare(k), 9)
        t.eq(R.Declare(k), 0)
        t.eq(k.settings:row("ui.intro").default, true, "the first one stands")
    end,

    ["rows: the addon's own kernel has them"] = function(t)
        t.eq(R.made, 9, "eight buttons rows (E-25, E-38: Banker and Deals) and the intro")
        t.ok(ns.settings:row("ui.intro") ~= nil, "ui.intro")
        t.ok(ns.settings:row("buttons.worldMap") ~= nil, "buttons.worldMap")
        t.ok(ns.settings:row("buttons.merchant") ~= nil, "buttons.merchant")
    end,

    ["rows: with the row on, the welcome shows at the first login"] = function(t)
        local k, c, diag = kernel()
        R.Declare(k)
        ns.Intro.Declare(k, diag)
        login(k, c)
        t.ok(introPanel(c) ~= nil, "the panel is made")
        t.eq(introShown(c), true)
    end,

    ["rows: with the row off in the saved data, the welcome does not show"] = function(t)
        local k, c, diag = kernel({ char = { settings = { ui = { intro = false } } } })
        R.Declare(k)
        ns.Intro.Declare(k, diag)
        login(k, c)
        t.eq(k.settings:get("ui.intro"), false)
        t.eq(introShown(c), false, "not on the screen")
    end,

    ["rows: a button row turned on makes that button, and only that one"] = function(t)
        -- The world map button is on by default (lead section 294): saved off
        -- here, so only the row turned on makes a button.
        local k, c = kernel({ account = { settings = { buttons = { merchant = true, worldMap = false } } } })
        R.Declare(k)
        c.setWindow("WorldMapFrame", {})
        c.setWindow("MerchantFrame", {})
        local shown = 0
        k:Module({ name = "arrow", provides = { OpenMenu = function() end } })
        k:Module({ name = "sellList", provides = { Show = function() shown = shown + 1 end } })
        ns.WindowButtons.Declare(k)
        login(k, c)
        local on = {}
        for _, b in ipairs(c.windowButtons) do
            if b.shown then on[#on + 1] = b.frame end
        end
        t.eq(on, { "MerchantFrame" })
        for _, b in ipairs(c.windowButtons) do b.click() end
        t.eq(shown, 1, "the click shows the sell list")
    end,
}
