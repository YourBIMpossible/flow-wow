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

return {
    ["rows: three rows, each with a label, a help line and the group"] = function(t)
        local k = kernel()
        t.eq(R.Declare(k), 3)
        for _, key in ipairs({ "ui.intro", "buttons.worldMap", "buttons.merchant" }) do
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

    -- Lead section 294 item 3: the merchant window's button is on unless the
    -- player turned it off. Before that flip row("buttons.merchant").default
    -- and get("buttons.merchant") were both false here.
    ["rows: the welcome is on for this character; for the account the map button is off, the merchant's on"] = function(t)
        local k, c = kernel()
        R.Declare(k)
        t.eq(k.settings:row("ui.intro").scope, "char")
        t.eq(k.settings:row("ui.intro").default, true)
        t.eq(k.settings:row("buttons.worldMap").scope, "account")
        t.eq(k.settings:row("buttons.worldMap").default, false)
        t.eq(k.settings:row("buttons.merchant").scope, "account")
        t.eq(k.settings:row("buttons.merchant").default, true)
        login(k, c)
        t.eq(k.settings:get("ui.intro"), true)
        t.eq(k.settings:get("buttons.worldMap"), false)
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

    -- At a default profile the merchant window has its button, and the
    -- world map none. Before the flip no button was made (#c.windowButtons 0).
    ["rows: at a default profile the merchant button is made, and only that one"] = function(t)
        local k, c = kernel()
        R.Declare(k)
        c.setWindow("WorldMapFrame", {})
        c.setWindow("MerchantFrame", {})
        local shown = 0
        k:Module({ name = "arrow", provides = { OpenMenu = function() end } })
        k:Module({ name = "sellList", provides = { Show = function() shown = shown + 1 end } })
        local buttons = ns.WindowButtons.Declare(k)
        login(k, c)
        t.eq(#c.windowButtons, 1, "one button")
        t.eq(c.windowButtons[1] and c.windowButtons[1].frame, "MerchantFrame")
        t.eq(c.windowButtons[1] and c.windowButtons[1].shown, true)
        t.eq(buttons.state(), { worldMap = "off", merchant = "shown" })
        for _, b in ipairs(c.windowButtons) do b.click() end
        t.eq(shown, 1, "the click shows the sell list")
    end,

    ["rows: they are the keys the welcome and the buttons read"] = function(t)
        t.eq(ns.Intro.SETTING, "ui.intro")
        local keys = {}
        for _, win in ipairs(ns.WindowButtons.WINDOWS) do keys[win.setting] = true end
        t.eq(keys, { ["buttons.worldMap"] = true, ["buttons.merchant"] = true })
    end,

    ["rows: a second declaration is refused"] = function(t)
        local k = kernel()
        t.eq(R.Declare(k), 3)
        t.eq(R.Declare(k), 0)
        t.eq(k.settings:row("ui.intro").default, true, "the first one stands")
    end,

    ["rows: the addon's own kernel has them"] = function(t)
        t.eq(R.made, 3)
        t.ok(ns.settings:row("ui.intro") ~= nil, "ui.intro")
        t.ok(ns.settings:row("buttons.worldMap") ~= nil, "buttons.worldMap")
        t.ok(ns.settings:row("buttons.merchant") ~= nil, "buttons.merchant")
    end,

    ["rows: with the row on, the welcome shows at the first login"] = function(t)
        local k, c, diag = kernel()
        R.Declare(k)
        ns.Intro.Declare(k, diag)
        login(k, c)
        local p = introPanel(c)
        t.ok(p ~= nil, "the panel is made")
        t.eq(p and p.shown, true)
    end,

    ["rows: with the row off in the saved data, the welcome does not show"] = function(t)
        local k, c, diag = kernel({ char = { settings = { ui = { intro = false } } } })
        R.Declare(k)
        ns.Intro.Declare(k, diag)
        login(k, c)
        t.eq(k.settings:get("ui.intro"), false)
        local p = introPanel(c)
        t.ok(p == nil or p.shown == false, "not on the screen")
    end,

    ["rows: a button row turned on makes that button, and only that one"] = function(t)
        local k, c = kernel({ account = { settings = { buttons = { merchant = true } } } })
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
