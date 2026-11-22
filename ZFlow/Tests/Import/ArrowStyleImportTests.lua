-- The arrow style on its way in from Flow (AS1): Flow's nav.arrowStyle lands
-- where the arrow reads it (layout.arrowStyle), and Flow's mark for the
-- one-time move to the modern arrow lands at layout.arrowModern. An old "3d"
-- that Flow never marked was the default of its day, so the import makes the
-- move itself. Every table below is made up; no real saved data is read.
local _, ns = ...

local Import = ns.Import

local function emptyAccount()
    return {
        schema = 1, settings = {}, layout = {}, imports = {},
        learned = { places = {}, flights = {}, prices = {}, facts = {}, fights = {} },
    }
end

local function emptyChar()
    return { schema = 1, settings = {}, layout = {}, learned = {}, state = {} }
end

local function from(nav)
    return Import.FromFlow({ nav = nav }, {})
end

-- The entry of a list (dropped or adjusted) for one Flow key, or nil.
local function entry(list, key)
    for i = 1, #list do
        if list[i].key == key then return list[i] end
    end
    return nil
end

-- Every line a merge report holds for one place: how many times the path
-- is listed as added, as kept and as skipped.
local function lines(report, path)
    local n = { added = 0, kept = 0, skipped = 0 }
    for _, at in ipairs(report.added) do
        if at == path then n.added = n.added + 1 end
    end
    for _, at in ipairs(report.kept) do
        if at == path then n.kept = n.kept + 1 end
    end
    for _, row in ipairs(report.skipped) do
        if row.path == path then n.skipped = n.skipped + 1 end
    end
    return n
end

local MARK = "account.layout.arrowModern"
local STYLE = "account.layout.arrowStyle"

-- An install the arrow has already run on: its mark is `mark`.
local function marked(mark, style)
    local account = emptyAccount()
    account.layout.arrowModern = mark
    account.layout.arrowStyle = style
    return account
end

local function settingsStyle(account)
    return type(account.settings.nav) == "table" and account.settings.nav.arrowStyle or nil
end

return {
    ["arrow style import: flat lands where the arrow reads it, not in settings"] = function(t)
        local result = from({ arrowStyle = "flat" })
        t.eq(result.ok, true)
        t.eq(result.account.layout.arrowStyle, "flat")
        t.eq(settingsStyle(result.account), nil, "nothing is written to the old place")
        t.eq(result.char.layout.arrowStyle, nil, "the style is not per character")
        t.eq(entry(result.dropped, "nav.arrowStyle"), nil, "it was not left behind")
    end,

    ["arrow style import: modern is carried as it is"] = function(t)
        local result = from({ arrowStyle = "modern", arrowModern = true })
        t.eq(result.account.layout.arrowStyle, "modern")
        t.eq(result.account.layout.arrowModern, true)
        t.eq(entry(result.adjusted, "nav.arrowStyle"), nil, "nothing was changed")
    end,

    ["arrow style import: Flow's mark is carried, no longer left behind"] = function(t)
        local result = from({ arrowStyle = "flat", arrowModern = true })
        t.eq(result.account.layout.arrowModern, true)
        t.eq(entry(result.dropped, "nav.arrowModern"), nil, "the mark is not dropped")
    end,

    ["arrow style import: a marked 3d stays 3d"] = function(t)
        local result = from({ arrowStyle = "3d", arrowModern = true })
        t.eq(result.account.layout.arrowStyle, "3d")
        t.eq(result.account.layout.arrowModern, true)
        t.eq(entry(result.adjusted, "nav.arrowStyle"), nil, "a chosen 3d is not adjusted")
    end,

    ["arrow style import: an unmarked 3d becomes modern, marked and listed as adjusted"] = function(t)
        local result = from({ arrowStyle = "3d" })
        t.eq(result.account.layout.arrowStyle, nil, "nothing saved is the modern arrow")
        t.eq(result.account.layout.arrowModern, true, "the move is marked as made")
        local changed = entry(result.adjusted, "nav.arrowStyle")
        t.ok(changed ~= nil, "the change is listed")
        if changed then
            t.eq(changed.from, "3d")
            t.eq(changed.to, "modern")
            t.ok(type(changed.reason) == "string" and changed.reason ~= "", "with a reason")
        end
        t.eq(result.record.counts.adjusted, #result.adjusted, "the record counts it")
    end,

    ["arrow style import: a 3d whose mark is false counts as unmarked"] = function(t)
        local result = from({ arrowStyle = "3d", arrowModern = false })
        t.eq(result.account.layout.arrowStyle, nil)
        t.eq(result.account.layout.arrowModern, true)
    end,

    ["arrow style import: a style this importer does not know is left behind"] = function(t)
        local result = from({ arrowStyle = "round" })
        t.eq(result.account.layout.arrowStyle, nil)
        t.eq(settingsStyle(result.account), nil)
        local left = entry(result.dropped, "nav.arrowStyle")
        t.ok(left ~= nil and left.why == "malformed", "listed as malformed")
        local odd = from({ arrowStyle = 3 })
        t.eq(odd.account.layout.arrowStyle, nil)
        t.ok(entry(odd.dropped, "nav.arrowStyle") ~= nil, "a number is no style either")
    end,

    ["arrow style import: a mark that is no true or false is left behind"] = function(t)
        local result = from({ arrowStyle = "flat", arrowModern = "yes" })
        t.eq(result.account.layout.arrowModern, nil)
        t.eq(result.account.layout.arrowStyle, "flat", "the style still comes in")
        local left = entry(result.dropped, "nav.arrowModern")
        t.ok(left ~= nil and left.why == "malformed", "listed as malformed")
    end,

    ["arrow style merge: an install with no style takes the imported one"] = function(t)
        local account = (Import.Merge(emptyAccount(), emptyChar(), from({ arrowStyle = "flat", arrowModern = true })))
        t.eq(account.layout.arrowStyle, "flat")
        t.eq(account.layout.arrowModern, true)
        t.eq(settingsStyle(account), nil)
    end,

    ["arrow style merge: a style the player already set is never replaced"] = function(t)
        for _, own in ipairs({ "modern", "3d", "flat" }) do
            for _, theirs in ipairs({ "modern", "3d", "flat" }) do
                local account = emptyAccount()
                account.layout.arrowStyle = own
                account.layout.arrowModern = true
                local out = (Import.Merge(account, emptyChar(), from({ arrowStyle = theirs, arrowModern = true })))
                t.eq(out.layout.arrowStyle, own, own .. " kept over an imported " .. theirs)
                t.eq(out.layout.arrowModern, true)
            end
        end
    end,

    ["arrow style merge: an unmarked 3d does not come in as 3d after the arrow has run"] = function(t)
        -- The arrow wrote its mark on the first login; the import comes later.
        local account = emptyAccount()
        account.layout.arrowModern = true
        local out = (Import.Merge(account, emptyChar(), from({ arrowStyle = "3d" })))
        t.eq(out.layout.arrowStyle, nil, "still the modern arrow")
        t.eq(out.layout.arrowModern, true)
    end,

    ["arrow style merge: the account given is not changed"] = function(t)
        local account = emptyAccount()
        local out = (Import.Merge(account, emptyChar(), from({ arrowStyle = "flat" })))
        t.eq(out.layout.arrowStyle, "flat")
        t.eq(account.layout.arrowStyle, nil)
    end,

    -- ---------------------------------------------------------------- SI1
    ["mark quiet: the same mark already there gets no report line"] = function(t)
        local account, _, report = Import.Merge(marked(true), emptyChar(), from({ arrowStyle = "flat", arrowModern = true }))
        t.eq(account.layout.arrowModern, true)
        local n = lines(report, MARK)
        t.eq(n.skipped, 0, "not listed as skipped")
        t.eq(n.kept, 0, "not listed as kept")
        t.eq(n.added, 0, "not listed as added")
    end,

    ["mark quiet: a mark that differs from the one already there gets no report line, and the one there stays"] = function(t)
        local account, _, report = Import.Merge(marked(true), emptyChar(), from({ arrowStyle = "flat", arrowModern = false }))
        t.eq(account.layout.arrowModern, true, "the install's own mark is kept")
        local n = lines(report, MARK)
        t.eq(n.skipped, 0, "not listed as skipped")
        t.eq(n.kept, 0, "not listed as kept")
        t.eq(n.added, 0)

        account, _, report = Import.Merge(marked(false), emptyChar(), from({ arrowStyle = "flat", arrowModern = true }))
        t.eq(account.layout.arrowModern, false, "a value already there is never replaced")
        n = lines(report, MARK)
        t.eq(n.skipped, 0)
        t.eq(n.kept, 0)
        t.eq(n.added, 0)
    end,

    ["mark quiet: the counts are the lists' lengths, without the mark"] = function(t)
        local _, _, report = Import.Merge(marked(true, "modern"), emptyChar(), from({ arrowStyle = "flat", arrowModern = false }))
        t.eq(report.counts.skipped, #report.skipped)
        t.eq(report.counts.kept, #report.kept)
        t.eq(report.counts.added, #report.added)
        t.eq(lines(report, MARK).skipped, 0)
        t.eq(lines(report, MARK).kept, 0)
    end,

    ["mark quiet: with no mark there yet, the mark is added and listed like any other row"] = function(t)
        local account, _, report = Import.Merge(emptyAccount(), emptyChar(), from({ arrowStyle = "flat", arrowModern = true }))
        t.eq(account.layout.arrowModern, true)
        t.eq(lines(report, MARK).added, 1, "an added row is still reported")
    end,

    ["mark quiet: the style beside it is still reported"] = function(t)
        local account, _, report = Import.Merge(marked(true, "modern"), emptyChar(), from({ arrowStyle = "flat", arrowModern = true }))
        t.eq(account.layout.arrowStyle, "modern")
        local n = lines(report, STYLE)
        t.eq(n.kept, 1, "the kept style is listed")
        t.eq(n.skipped, 1, "with its reason")
        t.eq(lines(report, MARK).skipped, 0)

        account, _, report = Import.Merge(marked(true, "flat"), emptyChar(), from({ arrowStyle = "flat", arrowModern = true }))
        t.eq(account.layout.arrowStyle, "flat")
        t.eq(lines(report, STYLE).skipped, 1, "the same style is still listed as skipped")
        t.eq(lines(report, MARK).skipped, 0)
    end,

    ["mark quiet: a per-character value at the same name is reported as before"] = function(t)
        -- Only the account's mark is the arrow's bookkeeping.
        local char = emptyChar()
        char.layout.arrowModern = true
        local imported = from({ arrowStyle = "flat", arrowModern = true })
        imported.char.layout.arrowModern = true
        local _, _, report = Import.Merge(marked(true), char, imported)
        t.eq(lines(report, "char.layout.arrowModern").skipped, 1)
        t.eq(lines(report, MARK).skipped, 0)
    end,

    -- ---------------------------------------------------------------- IQ1
    ["mark typed: a held mark that is a string gives way to the imported mark, and is reported"] = function(t)
        local account, _, report = Import.Merge(marked("yes"), emptyChar(), from({ arrowStyle = "flat", arrowModern = true }))
        t.eq(account.layout.arrowModern, true, "a string is no mark; the imported one lands")
        local n = lines(report, MARK)
        t.eq(n.added, 1, "listed as added")
        t.eq(n.kept, 0)
        t.eq(n.skipped, 0)

        account, _, report = Import.Merge(marked("true"), emptyChar(), from({ arrowStyle = "flat", arrowModern = false }))
        t.eq(account.layout.arrowModern, false)
        t.eq(lines(report, MARK).added, 1)
    end,

    ["mark typed: a held mark that is a number or a table gives way too"] = function(t)
        local account, _, report = Import.Merge(marked(1), emptyChar(), from({ arrowStyle = "flat", arrowModern = true }))
        t.eq(account.layout.arrowModern, true)
        t.eq(lines(report, MARK).added, 1)

        account, _, report = Import.Merge(marked({ on = true }), emptyChar(), from({ arrowStyle = "flat", arrowModern = true }))
        t.eq(account.layout.arrowModern, true)
        t.eq(lines(report, MARK).added, 1)
    end,

    ["mark typed: a held boolean, true or false, stays quiet"] = function(t)
        for _, held in ipairs({ true, false }) do
            local account, _, report = Import.Merge(marked(held), emptyChar(),
                from({ arrowStyle = "flat", arrowModern = not held }))
            t.eq(account.layout.arrowModern, held)
            local n = lines(report, MARK)
            t.eq(n.added + n.kept + n.skipped, 0, "no report line")
        end
    end,
}
