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
}
