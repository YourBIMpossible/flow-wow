-- The settings page over the fake client: what it lays out from the kernel
-- rows, what a change saves, what it refuses and that a refusal changes
-- nothing. No frame and no game client is involved.
local _, ns = ...

local P = ns.SettingsPage

local ROWS = {
    { key = "sell.autoJunk", scope = "char", type = "bool", default = false, label = "Sell junk",
      help = "Sells grey items.", group = "Vendor" },
    { key = "arrow.size", scope = "account", type = "number", default = 5, min = 1, max = 10,
      label = "Arrow size", group = "Arrow" },
    { key = "arrow.look", scope = "account", type = "choice", choices = { "Modern", "3D", "flat" },
      default = "Modern", label = "Arrow look", group = "Arrow" },
    { key = "note.text", scope = "char", type = "string", default = "hello", label = "Note" },
    { key = "arrow.points", scope = "account", type = "table", path = "layout.points",
      label = "Arrow places", group = "Arrow" },
    { key = "sell.confirm", scope = "char", type = "bool", default = true, label = "Ask first", group = "Vendor",
      requires = function(settings) return settings:get("sell.autoJunk") == true end },
}

-- opts: rows (instead of ROWS), noLogin, saved = { account =, char = }.
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    if opts.saved and opts.saved.account then c.setSaved(ns.id.accountDB, opts.saved.account) end
    if opts.saved and opts.saved.char then c.setSaved(ns.id.charDB, opts.saved.char) end
    local k = ns.Kernel({}, c)
    local rows = opts.rows or ROWS
    for i = 1, #rows do
        local row = {}
        for key, value in pairs(rows[i]) do row[key] = value end
        k:Setting(row)
    end
    k:Boot()
    if not opts.noLogin then
        c.fire("ADDON_LOADED", ns.id.addon)
        c.fire("PLAYER_LOGIN")
        c.fire("PLAYER_ENTERING_WORLD")
    end
    return k, c
end

local function entry(view, key)
    for g = 1, #view.groups do
        local rows = view.groups[g].rows
        for i = 1, #rows do
            if rows[i].key == key then return rows[i], view.groups[g] end
        end
    end
    return nil
end

local function stored(c, db, a, b)
    local settings = c.saved(db).settings
    local section = type(settings) == "table" and settings[a] or nil
    if type(section) ~= "table" then return nil end
    return section[b]
end

return {
    ["view: the rows stand in their groups, groups in the order first declared, rows in the order declared"] = function(t)
        local k = start()
        local view = P.View(k)
        t.eq(view.loaded, true)
        local names, keys = {}, {}
        for g = 1, #view.groups do
            names[g] = view.groups[g].name
            keys[g] = {}
            for i = 1, #view.groups[g].rows do keys[g][i] = view.groups[g].rows[i].key end
        end
        t.eq(names, { "Vendor", "Arrow", P.GROUP_OTHER })
        t.eq(keys, {
            { "sell.autoJunk", "sell.confirm" },
            { "arrow.size", "arrow.look", "arrow.points" },
            { "note.text" },
        })
        t.eq(view.count, 6)
    end,

    ["view: each row says its kind, label, help, value and who it is saved for"] = function(t)
        local k = start()
        local view = P.View(k)
        local junk = entry(view, "sell.autoJunk")
        t.eq(junk.kind, "toggle")
        t.eq(junk.label, "Sell junk")
        t.eq(junk.help, "Sells grey items.")
        t.eq(junk.value, false)
        t.eq(junk.shown, "off")
        t.eq(junk.savedFor, "this character")
        t.eq(junk.settable, true)
        local size = entry(view, "arrow.size")
        t.eq(size.kind, "number")
        t.eq(size.value, 5)
        t.eq(size.shown, "5")
        t.eq(size.min, 1)
        t.eq(size.max, 10)
        t.eq(size.savedFor, "account")
        local look = entry(view, "arrow.look")
        t.eq(look.kind, "choice")
        t.eq(look.value, "Modern")
        t.eq(look.choices, { "Modern", "3D", "flat" })
        local note = entry(view, "note.text")
        t.eq(note.kind, "text")
        t.eq(note.value, "hello")
        t.eq(note.help, nil, "no help is made up")
    end,

    ["view: the choices handed out are a copy; changing them does not change the row"] = function(t)
        local k = start()
        local look = entry(P.View(k), "arrow.look")
        look.choices[1] = "changed"
        t.eq(k.settings:row("arrow.look").choices[1], "Modern")
        t.eq(entry(P.View(k), "arrow.look").choices, { "Modern", "3D", "flat" })
    end,

    ["view: the stored value is shown, not the default"] = function(t)
        local k = start({ saved = {
            account = { settings = { arrow = { size = 8, look = "flat" } } },
            char = { settings = { sell = { autoJunk = true } } },
        } })
        local view = P.View(k)
        t.eq(entry(view, "arrow.size").value, 8)
        t.eq(entry(view, "arrow.look").shown, "flat")
        t.eq(entry(view, "sell.autoJunk").shown, "on")
    end,

    ["view: a table row is a place, is not spelled out and cannot be set from the page"] = function(t)
        local k = start()
        local place = entry(P.View(k), "arrow.points")
        t.eq(place.kind, "place")
        t.eq(place.value, nil, "the table is not handed out")
        t.eq(place.shown, "not set", "never 0 or off")
        t.eq(place.settable, false)
        t.ok(type(place.why) == "string" and place.why ~= "", "it says why")
        k = start({ saved = { account = { layout = { points = { x = 1 } } } } })
        t.eq(entry(P.View(k), "arrow.points").shown, "set")
    end,

    ["view: a row whose requires says no is shown as not applying and cannot be set"] = function(t)
        local k = start()
        local confirm = entry(P.View(k), "sell.confirm")
        t.eq(confirm.available, false)
        t.eq(confirm.settable, false)
        t.eq(confirm.why, P.NOT_NOW)
        t.eq(P.Set(k, "sell.autoJunk", true), true)
        confirm = entry(P.View(k), "sell.confirm")
        t.eq(confirm.available, true)
        t.eq(confirm.settable, true)
        t.eq(confirm.why, nil)
    end,

    ["view: no rows gives no groups"] = function(t)
        local k = start({ rows = {} })
        local view = P.View(k)
        t.eq(view.groups, {})
        t.eq(view.count, 0)
    end,

    ["view changes nothing"] = function(t)
        local k, c = start()
        P.View(k)
        P.View(k)
        t.eq(c.saved(ns.id.accountDB).settings, {}, "nothing under the account settings")
        t.eq(c.saved(ns.id.charDB).settings, {}, "nothing under the character settings")
    end,

    ["before saved data is loaded the rows are listed without values and nothing can be set"] = function(t)
        local k, c = start({ noLogin = true })
        local view = P.View(k)
        t.eq(view.loaded, false)
        t.eq(view.count, 6)
        local junk = entry(view, "sell.autoJunk")
        t.eq(junk.value, nil, "a default is not shown as the saved value")
        t.eq(junk.shown, "")
        t.eq(junk.settable, false)
        t.eq(junk.why, P.NOT_LOADED)
        local ok, why = P.Set(k, "sell.autoJunk", true)
        t.eq(ok, false)
        t.eq(why, P.NOT_LOADED)
        t.eq(c.savedExists(ns.id.charDB), false, "nothing was read or written")
    end,

    ["set: a toggle is saved at the row's own scope"] = function(t)
        local k, c = start()
        local ok, why = P.Set(k, "sell.autoJunk", true)
        t.eq(ok, true)
        t.eq(why, nil)
        t.eq(k.settings:get("sell.autoJunk"), true)
        t.eq(stored(c, ns.id.charDB, "sell", "autoJunk"), true)
        t.eq(stored(c, ns.id.accountDB, "sell", "autoJunk"), nil, "not in the other scope")
        t.eq(P.Set(k, "sell.autoJunk", false), true)
        t.eq(stored(c, ns.id.charDB, "sell", "autoJunk"), false)
    end,

    ["set: a toggle given anything but true or false is refused and changes nothing"] = function(t)
        local k, c = start()
        for _, value in ipairs({ "on", 1, 0, {} }) do
            local ok, why = P.Set(k, "sell.autoJunk", value)
            t.eq(ok, false)
            t.ok(type(why) == "string" and why ~= "", "a reason is given")
        end
        local ok = P.Set(k, "sell.autoJunk", nil)
        t.eq(ok, false, "nothing is not a value")
        t.eq(stored(c, ns.id.charDB, "sell", "autoJunk"), nil, "nothing stored")
    end,

    ["set: a number inside the limits is saved; outside them or not a number is refused with the reason"] = function(t)
        local k, c = start()
        t.eq(P.Set(k, "arrow.size", 10), true)
        t.eq(stored(c, ns.id.accountDB, "arrow", "size"), 10)
        local ok, why = P.Set(k, "arrow.size", 11)
        t.eq(ok, false)
        t.ok(why:find("10", 1, true) ~= nil, "the highest value is named")
        ok, why = P.Set(k, "arrow.size", 0)
        t.eq(ok, false)
        t.ok(why:find("1", 1, true) ~= nil, "the lowest value is named")
        for _, value in ipairs({ "7", true, 0 / 0, math.huge, -math.huge }) do
            ok = P.Set(k, "arrow.size", value)
            t.eq(ok, false)
        end
        t.eq(stored(c, ns.id.accountDB, "arrow", "size"), 10, "unchanged by the refusals")
    end,

    ["set: a choice takes one of its choices exactly; anything else is refused naming them"] = function(t)
        local k, c = start()
        t.eq(P.Set(k, "arrow.look", "3D"), true)
        t.eq(stored(c, ns.id.accountDB, "arrow", "look"), "3D")
        local ok, why = P.Set(k, "arrow.look", "3d")
        t.eq(ok, false, "the page hands over the choice itself, so capitals count")
        t.ok(why:find("Modern, 3D, flat", 1, true) ~= nil, "the choices are named")
        t.eq(P.Set(k, "arrow.look", 3), false)
        t.eq(stored(c, ns.id.accountDB, "arrow", "look"), "3D", "unchanged by the refusals")
    end,

    ["set: a text row takes text as given, capitals kept; anything else is refused"] = function(t)
        local k, c = start()
        t.eq(P.Set(k, "note.text", "Hello There"), true)
        t.eq(stored(c, ns.id.charDB, "note", "text"), "Hello There")
        t.eq(P.Set(k, "note.text", 5), false)
        t.eq(stored(c, ns.id.charDB, "note", "text"), "Hello There")
    end,

    ["set: a place row is refused and what is stored there stays"] = function(t)
        local k, c = start({ saved = { account = { layout = { points = { x = 1 } } } } })
        local ok, why = P.Set(k, "arrow.points", { x = 2 })
        t.eq(ok, false)
        t.eq(why, P.NOT_FROM_HERE)
        ok = P.Set(k, "arrow.points", nil)
        t.eq(ok, false, "the page does not clear a place either")
        t.eq(c.saved(ns.id.accountDB).layout.points, { x = 1 })
    end,

    ["set: an unknown key is refused with the reason"] = function(t)
        local k, c = start()
        local ok, why = P.Set(k, "no.such", true)
        t.eq(ok, false)
        t.ok(why:find("no.such", 1, true) ~= nil, "the key is named")
        ok = P.Set(k, nil, true)
        t.eq(ok, false)
        ok = P.Set(k, "all", true)
        t.eq(ok, false, "all is not a key")
        t.eq(c.saved(ns.id.charDB).settings, {}, "nothing stored")
    end,

    ["set: a row that does not apply now is refused"] = function(t)
        local k, c = start()
        local ok, why = P.Set(k, "sell.confirm", false)
        t.eq(ok, false)
        t.eq(why, P.NOT_NOW)
        t.eq(stored(c, ns.id.charDB, "sell", "confirm"), nil, "nothing stored")
    end,

    ["set: the settings model's rule for a key is asked as well"] = function(t)
        -- The model holds auction.chartClick as a yes-or-no choice. A kernel
        -- row that would take a number for it is still refused.
        local k, c = start({ rows = {
            { key = "auction.chartClick", scope = "account", type = "number", default = 1, label = "Chart click" },
        } })
        local ok, why = P.Set(k, "auction.chartClick", 2)
        t.eq(ok, false)
        t.ok(why:find("expected true or false", 1, true) ~= nil, "with the model's reason")
        t.eq(k.settings:get("auction.chartClick"), 1, "unchanged")
        t.eq(stored(c, ns.id.accountDB, "auction", "chartClick"), nil, "nothing stored")
    end,

    ["set: a write the store refuses is reported with its reason and reads back unchanged"] = function(t)
        local k = start()
        k.store.blocked.char = "the saved data could not be brought up to date"
        local ok, why = P.Set(k, "sell.autoJunk", true)
        t.eq(ok, false)
        t.ok(why:find("the saved data could not be brought up to date", 1, true) ~= nil, "the store's reason")
        t.eq(k.settings:get("sell.autoJunk"), false, "unchanged")
    end,

    ["set: a row with a place of its own is saved there"] = function(t)
        local k, c = start({ rows = {
            { key = "arrow.big", scope = "account", type = "bool", default = false, path = "layout.big.on",
              label = "Big arrow" },
        } })
        t.eq(P.Set(k, "arrow.big", true), true)
        t.eq(c.saved(ns.id.accountDB).layout.big.on, true)
        t.eq(c.saved(ns.id.accountDB).settings, {}, "nothing under settings")
    end,

    ["the page offers no reset"] = function(t)
        t.eq(P.Reset, nil)
        t.eq(P.ResetAll, nil)
    end,

    ["no player text of the page spells the old name"] = function(t)
        for _, text in ipairs({ P.NOT_LOADED, P.NOT_NOW, P.NOT_FROM_HERE, P.GROUP_OTHER }) do
            t.ok(type(text) == "string" and text ~= "", "the text is there")
            t.ok(not text:lower():find("flow", 1, true), "the text does not spell it")
        end
    end,
}
