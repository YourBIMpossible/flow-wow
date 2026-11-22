-- The setting word of the slash command over the fake client: what it
-- lists, what it changes, what it refuses and that a refusal changes
-- nothing. No game client is involved.
local _, ns = ...

local S = ns.SettingsSlash

local ROWS = {
    { key = "sell.autoJunk", scope = "char", type = "bool", default = false, label = "Sell junk" },
    { key = "arrow.size", scope = "account", type = "number", default = 5, min = 1, max = 10, label = "Arrow size" },
    { key = "arrow.look", scope = "account", type = "choice", choices = { "Modern", "3D", "flat" },
      default = "Modern", label = "Arrow look" },
    { key = "note.text", scope = "char", type = "string", default = "hello", label = "Note" },
    { key = "arrow.points", scope = "account", type = "table", path = "layout.points", label = "Arrow places" },
}

-- opts: rows (instead of ROWS), noLogin, noDiag, saved = { account =, char = }.
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    if opts.saved and opts.saved.account then c.setSaved(ns.id.accountDB, opts.saved.account) end
    if opts.saved and opts.saved.char then c.setSaved(ns.id.charDB, opts.saved.char) end
    local k = ns.Kernel({}, c)
    local d = (not opts.noDiag) and ns.Diag.Start(k) or nil
    local rows = opts.rows or ROWS
    for i = 1, #rows do
        local row = {}
        for key, value in pairs(rows[i]) do row[key] = value end
        k:Setting(row)
    end
    local s = S.Start(k, d)
    k:Boot()
    if not opts.noLogin then
        c.fire("ADDON_LOADED", ns.id.addon)
        c.fire("PLAYER_LOGIN")
        c.fire("PLAYER_ENTERING_WORLD")
    end
    return k, c, s, d
end

-- Types the slash command and returns the lines it printed for that.
local function typed(c, rest)
    local from = #c.printed
    c.slashes[ns.id.slash](rest)
    local out = {}
    for i = from + 1, #c.printed do out[#out + 1] = c.printed[i] end
    return out
end

local function has(lines, text)
    for i = 1, #lines do
        if lines[i]:find(text, 1, true) then return true end
    end
    return false
end

local function lineWith(lines, text)
    for i = 1, #lines do
        if lines[i]:find(text, 1, true) then return lines[i] end
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
    ["the word is added to the slash command; without diag nothing is added and nothing raises"] = function(t)
        local _, _, _, d = start()
        t.eq(type(d.commands.setting), "function", "the word is there")
        local ok = pcall(start, { noDiag = true })
        t.ok(ok, "no diag: starts without raising")
    end,

    ["list: every row with its key, label, value and scope, in the order declared"] = function(t)
        local _, c = start()
        local lines = typed(c, "setting")
        local at = {}
        for i = 1, #ROWS do
            local line = lineWith(lines, ROWS[i].key)
            t.ok(line ~= nil, ROWS[i].key .. " is listed")
            t.ok(line and line:find(ROWS[i].label, 1, true), ROWS[i].key .. " has its label")
            for n = 1, #lines do
                if lines[n] == line then at[i] = n end
            end
        end
        for i = 2, #ROWS do t.ok(at[i - 1] < at[i], "in the order declared: " .. ROWS[i].key) end
        local junk = lineWith(lines, "sell.autoJunk")
        t.ok(junk:find("off", 1, true), "a bool that is false reads off")
        t.ok(junk:find("this character", 1, true), "char scope is named")
        local size = lineWith(lines, "arrow.size")
        t.ok(size:find("= 5", 1, true), "a number reads as the number")
        t.ok(size:find("account", 1, true), "account scope is named")
        t.ok(lineWith(lines, "arrow.look"):find("Modern", 1, true), "a choice reads as the choice")
        t.ok(lineWith(lines, "note.text"):find("hello", 1, true), "text reads as the text")
        for i = 1, #lines do
            t.ok(lines[i]:find(ns.id.title, 1, true) == 1, "each line starts with the title")
        end
    end,

    ["list: the stored value is shown, not the default; a table row is not spelled out"] = function(t)
        local _, c = start({ saved = {
            char = { settings = { sell = { autoJunk = true } } },
            account = { layout = { points = { 1, 2, 3 } } },
        } })
        local lines = typed(c, "setting")
        t.ok(lineWith(lines, "sell.autoJunk"):find("= on", 1, true), "stored true reads on")
        local points = lineWith(lines, "arrow.points")
        t.ok(points:find("set", 1, true), "a stored table is said to be set")
        t.ok(not points:find("table:", 1, true), "no table address")
    end,

    ["list: a table row with nothing stored reads not set, never 0 or off"] = function(t)
        local _, c = start()
        local points = lineWith(typed(c, "setting"), "arrow.points")
        t.ok(points:find("not set", 1, true), "not set")
    end,

    ["list: no rows is said in one line"] = function(t)
        local _, c = start({ rows = {} })
        local lines = typed(c, "setting")
        t.eq(#lines, 1, "one line")
        t.ok(has(lines, "no settings"), "says there are none")
    end,

    ["list changes nothing"] = function(t)
        local _, c = start()
        typed(c, "setting")
        t.eq(c.saved(ns.id.charDB).settings, {}, "char settings untouched")
        t.eq(c.saved(ns.id.accountDB).settings, {}, "account settings untouched")
    end,

    ["a key alone shows that one row and how to change it"] = function(t)
        local _, c = start()
        local lines = typed(c, "setting sell.autojunk")
        t.ok(has(lines, "sell.autoJunk"), "the row, by its own key")
        t.ok(has(lines, "on or off"), "what it takes")
        t.ok(not has(lines, "arrow.size"), "no other row")
        lines = typed(c, "setting arrow.size")
        t.ok(has(lines, "1 to 10"), "a number's limits are said")
        lines = typed(c, "setting arrow.look")
        t.ok(has(lines, "Modern, 3D, flat"), "a choice's choices are said")
    end,

    ["bool: on and off are saved at the row's own scope"] = function(t)
        local k, c = start()
        local lines = typed(c, "setting sell.autojunk on")
        t.eq(k.settings:get("sell.autoJunk"), true, "on")
        t.eq(stored(c, ns.id.charDB, "sell", "autoJunk"), true, "in the character's data")
        t.eq(stored(c, ns.id.accountDB, "sell", "autoJunk"), nil, "not in the account's")
        t.ok(has(lines, "sell.autoJunk is now on"), "says so")
        t.ok(has(lines, "was off"), "and what it was")
        t.ok(has(lines, "this character"), "and where it is saved")
        lines = typed(c, "setting sell.autojunk off")
        t.eq(k.settings:get("sell.autoJunk"), false, "off")
        t.eq(stored(c, ns.id.charDB, "sell", "autoJunk"), false, "stored as false, not removed")
        t.ok(has(lines, "sell.autoJunk is now off"), "says so")
    end,

    ["bool: anything but on or off is refused and changes nothing"] = function(t)
        local k, c = start()
        typed(c, "setting sell.autojunk on")
        for _, word in ipairs({ "true", "1", "yes", "maybe", "0", "onn" }) do
            local lines = typed(c, "setting sell.autojunk " .. word)
            t.eq(k.settings:get("sell.autoJunk"), true, word .. ": still on")
            t.ok(has(lines, "not changed"), word .. ": refused")
            t.ok(has(lines, "on or off"), word .. ": with the reason")
        end
    end,

    ["the key is matched whatever its capitals, and the row's own spelling is used"] = function(t)
        local k, c = start()
        -- The slash command hands the word everything lower-cased.
        typed(c, "setting SELL.AUTOJUNK ON")
        t.eq(k.settings:get("sell.autoJunk"), true, "set")
        t.eq(k.settings:get("sell.autojunk"), nil, "no row was made up under the typed spelling")
    end,

    ["an unknown key is refused with the reason and changes nothing"] = function(t)
        local k, c = start()
        local before = { char = c.saved(ns.id.charDB).settings, account = c.saved(ns.id.accountDB).settings }
        local lines = typed(c, "setting sell.nothing on")
        t.ok(has(lines, "no setting is called sell.nothing"), "the reason")
        t.eq(c.saved(ns.id.charDB).settings, {}, "char settings untouched")
        t.eq(c.saved(ns.id.accountDB).settings, {}, "account settings untouched")
        t.eq(before.char, {}, "and were empty")
        t.eq(k.settings:row("sell.nothing"), nil, "no row was declared")
        lines = typed(c, "setting sell.nothing")
        t.ok(has(lines, "no setting is called sell.nothing"), "also when only asked about")
    end,

    ["number: a value inside the limits is saved as a number"] = function(t)
        local k, c = start()
        local lines = typed(c, "setting arrow.size 7")
        t.eq(k.settings:get("arrow.size"), 7, "a number, not text")
        t.eq(stored(c, ns.id.accountDB, "arrow", "size"), 7, "in the account's data")
        t.ok(has(lines, "arrow.size is now 7"), "says so")
        t.ok(has(lines, "was 5"), "and what it was")
        typed(c, "setting arrow.size 2.5")
        t.eq(k.settings:get("arrow.size"), 2.5, "a fraction")
        typed(c, "setting arrow.size 1")
        t.eq(k.settings:get("arrow.size"), 1, "the lowest allowed")
        typed(c, "setting arrow.size 10")
        t.eq(k.settings:get("arrow.size"), 10, "the highest allowed")
    end,

    ["number: outside the limits or not a number is refused with the reason"] = function(t)
        local k, c = start()
        typed(c, "setting arrow.size 7")
        local lines = typed(c, "setting arrow.size 0")
        t.eq(k.settings:get("arrow.size"), 7, "below: unchanged")
        t.ok(has(lines, "below the lowest value allowed (1)"), "below: the reason")
        lines = typed(c, "setting arrow.size 11")
        t.eq(k.settings:get("arrow.size"), 7, "above: unchanged")
        t.ok(has(lines, "above the highest value allowed (10)"), "above: the reason")
        for _, word in ipairs({ "big", "on", "0x5", "inf", "nan", "1e1", "5 6", "--5" }) do
            lines = typed(c, "setting arrow.size " .. word)
            t.eq(k.settings:get("arrow.size"), 7, word .. ": unchanged")
            t.ok(has(lines, "is not a number"), word .. ": the reason")
        end
    end,

    ["number: a row without limits takes any plain number, negative too"] = function(t)
        local k, c = start({ rows = {
            { key = "x.offset", scope = "account", type = "number", default = 0, label = "Offset" },
        } })
        typed(c, "setting x.offset -40")
        t.eq(k.settings:get("x.offset"), -40)
        local lines = typed(c, "setting x.offset")
        t.ok(has(lines, "a number"), "what it takes, with no limits made up")
        t.ok(not has(lines, " to "), "no range is named")
    end,

    ["choice: one of the choices is saved in the row's own spelling"] = function(t)
        local k, c = start()
        local lines = typed(c, "setting arrow.look 3d")
        t.eq(k.settings:get("arrow.look"), "3D", "the row's spelling, not the typed one")
        t.ok(has(lines, "arrow.look is now 3D"), "says so")
        t.ok(has(lines, "was Modern"), "and what it was")
        typed(c, "setting arrow.look flat")
        t.eq(k.settings:get("arrow.look"), "flat")
    end,

    ["choice: anything else is refused, naming the choices"] = function(t)
        local k, c = start()
        local lines = typed(c, "setting arrow.look round")
        t.eq(k.settings:get("arrow.look"), "Modern", "unchanged")
        t.eq(stored(c, ns.id.accountDB, "arrow", "look"), nil, "nothing stored")
        t.ok(has(lines, "not changed"), "refused")
        t.ok(has(lines, "Modern, 3D, flat"), "the choices")
    end,

    ["text and table rows are listed but not set from here"] = function(t)
        local k, c = start()
        local lines = typed(c, "setting note.text something")
        t.eq(k.settings:get("note.text"), "hello", "text unchanged")
        t.ok(has(lines, "not changed"), "text refused")
        lines = typed(c, "setting arrow.points on")
        t.eq(k.settings:get("arrow.points"), nil, "table unchanged")
        t.eq(c.saved(ns.id.accountDB).layout.points, nil, "nothing stored at its place")
        t.ok(has(lines, "not changed"), "table refused")
    end,

    ["a row with a place of its own is saved there"] = function(t)
        local k, c = start({ rows = {
            { key = "arrow.style", scope = "account", type = "choice", choices = { "modern", "flat" },
              default = "modern", path = "layout.arrowStyle", label = "Arrow style" },
        } })
        typed(c, "setting arrow.style flat")
        t.eq(k.settings:get("arrow.style"), "flat")
        t.eq(c.saved(ns.id.accountDB).layout.arrowStyle, "flat", "at the row's own place")
        t.eq(c.saved(ns.id.accountDB).settings, {}, "nothing under settings")
    end,

    ["the settings model's rule for a key is asked as well"] = function(t)
        -- The model holds auction.chartClick as a yes-or-no choice. A kernel
        -- row that would take a number for it is still refused.
        local k, c = start({ rows = {
            { key = "auction.chartClick", scope = "account", type = "number", default = 1, label = "Chart click" },
        } })
        local lines = typed(c, "setting auction.chartclick 2")
        t.eq(k.settings:get("auction.chartClick"), 1, "unchanged")
        t.eq(stored(c, ns.id.accountDB, "auction", "chartClick"), nil, "nothing stored")
        t.ok(has(lines, "not changed"), "refused")
        t.ok(has(lines, "expected true or false"), "with the model's reason")
    end,

    ["a write the store refuses is reported with its reason and reads back unchanged"] = function(t)
        local k, c = start()
        k.store.blocked.char = "the saved data could not be brought up to date"
        local lines = typed(c, "setting sell.autojunk on")
        t.eq(k.settings:get("sell.autoJunk"), false, "unchanged")
        t.ok(has(lines, "not changed"), "refused")
        t.ok(has(lines, "the saved data could not be brought up to date"), "the store's reason")
        t.ok(not has(lines, "is now"), "no claim that it changed")
    end,

    ["before saved data is loaded nothing is listed as a value and nothing is set"] = function(t)
        local _, c = start({ noLogin = true })
        local lines = typed(c, "setting")
        t.eq(#lines, 1, "one line")
        t.ok(has(lines, "not loaded yet"), "says why")
        lines = typed(c, "setting sell.autojunk on")
        t.ok(has(lines, "not loaded yet"), "a change is refused the same way")
        t.eq(c.savedExists(ns.id.charDB), false, "nothing was read or written")
    end,

    ["Run: the same answers without the slash command"] = function(t)
        local k = start()
        local lines, changed = S.Run(k, "sell.autojunk on")
        t.eq(changed, true, "changed")
        t.eq(k.settings:get("sell.autoJunk"), true)
        t.eq(type(lines), "table")
        local _, afterRefusal = S.Run(k, "sell.autojunk maybe")
        t.eq(afterRefusal, false, "a refusal is not a change")
        lines, changed = S.Run(k, "")
        t.eq(changed, false, "a list is not a change")
        t.ok(#lines >= #ROWS, "a line for each row")
        lines, changed = S.Run(k, nil)
        t.eq(changed, false, "no text is a list")
    end,

    ["other words of the slash command still work"] = function(t)
        local _, c = start()
        local lines = typed(c, "")
        t.ok(has(lines, ns.id.slash .. " diag"), "the plain command says what it said")
    end,
}
