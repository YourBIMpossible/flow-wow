-- The help word with a text that is not a command (G54, lead section 362):
-- as the predecessor's help did, it lists only the help that has the text,
-- in the word or in what the word does, and says so when nothing has it.
-- No game client is involved.
local _, ns = ...

local function f() end
local COMMANDS = { arrow = f, diag = f, setting = f, sell = f, notrun = "text" }
local HELP = {
    arrow = "show, hide or reset the arrow",
    diag = "save a diagnostic snapshot",
    setting = "list the settings, show one, or change one",
    sell = "what would be sold at a vendor",
    notrun = "a snapshot of nothing",
}

local function start()
    local c = ns.make.fakeClient()
    local k = ns.Kernel({}, c)
    ns.Diag.Start(k)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return c
end

local function said(c, rest)
    local before = #c.printed
    c.slashes[ns.id.slash](rest)
    local out = {}
    for i = before + 1, #c.printed do out[#out + 1] = c.printed[i] end
    return out
end

return {
    ["help search: a text in what a word does lists that word only"] = function(t)
        t.eq(ns.Diag.HelpFor(COMMANDS, HELP, "/x", "snapshot"), {
            'commands about "snapshot" (1):',
            "/x diag - save a diagnostic snapshot",
        })
    end,

    ["help search: a text inside a word lists it, a-z with the others that have it"] = function(t)
        t.eq(ns.Diag.HelpFor(COMMANDS, HELP, "/x", "se"), {
            'commands about "se" (3):',
            "/x arrow - show, hide or reset the arrow",
            "/x sell - what would be sold at a vendor",
            "/x setting - list the settings, show one, or change one",
        })
    end,

    ["help search: the text is read whatever its case and spacing, several words as one"] = function(t)
        local want = { 'commands about "the arrow" (1):', "/x arrow - show, hide or reset the arrow" }
        t.eq(ns.Diag.HelpFor(COMMANDS, HELP, "/x", "the arrow"), want)
        t.eq(ns.Diag.HelpFor(COMMANDS, HELP, "/x", "  The ARROW  "), want)
    end,

    ["help search: the text is plain, never a pattern"] = function(t)
        local lines = ns.Diag.HelpFor(COMMANDS, HELP, "/x", "%a+")
        t.eq(lines, { 'no help has "%a+". /x help lists every command.' })
        t.eq(ns.Diag.HelpFor(COMMANDS, HELP, "/x", "("), { 'no help has "(". /x help lists every command.' })
    end,

    ["help search: nothing has the text: one line that says so and points at help"] = function(t)
        t.eq(ns.Diag.HelpFor(COMMANDS, HELP, "/x", "zzz"), { 'no help has "zzz". /x help lists every command.' })
    end,

    ["help search: a word that cannot run is not found by its text"] = function(t)
        t.eq(ns.Diag.HelpFor(COMMANDS, HELP, "/x", "nothing"),
            { 'no help has "nothing". /x help lists every command.' })
    end,

    ["help search: a word with no description is found by its name only"] = function(t)
        t.eq(ns.Diag.HelpFor({ bare = f }, {}, "/x", "bar"),
            { 'commands about "bar" (1):', "/x bare - " .. ns.Diag.NO_HELP })
        t.eq(ns.Diag.HelpFor({ bare = f }, {}, "/x", "description"),
            { 'no help has "description". /x help lists every command.' })
    end,

    ["help search: a command, a page number and no text answer as before"] = function(t)
        t.eq(ns.Diag.HelpFor(COMMANDS, HELP, "/x", "sell"), { "/x sell - what would be sold at a vendor" })
        t.eq(ns.Diag.HelpFor(COMMANDS, HELP, "/x", "sell more"), { "/x sell - what would be sold at a vendor" })
        local all = ns.Diag.HelpLines(COMMANDS, HELP, "/x")
        t.eq(ns.Diag.HelpFor(COMMANDS, HELP, "/x", ""), all)
        t.eq(ns.Diag.HelpFor(COMMANDS, HELP, "/x", nil), all)
        t.eq(ns.Diag.HelpFor(COMMANDS, HELP, "/x", "1"), all)
    end,

    ["slash help search: the addon's own words are searched and nothing is saved"] = function(t)
        local c = start()
        local snaps = c.saved(ns.id.accountDB).diag.count
        local lines = said(c, "help snapshot")
        t.ok(#lines >= 2, "nothing found for snapshot")
        t.ok(lines[1]:find('commands about "snapshot"', 1, true) ~= nil, lines[1])
        local diag = false
        for i = 2, #lines do
            if lines[i]:find(ns.id.slash .. " diag - ", 1, true) then diag = true end
        end
        t.ok(diag, "the diag word was not found by its description")
        local none = said(c, "help qqzzqq")
        t.eq(#none, 1)
        t.ok(none[1]:find('no help has "qqzzqq"', 1, true) ~= nil, none[1])
        t.eq(c.saved(ns.id.accountDB).diag.count, snaps, "help search took a snapshot")
    end,
}
