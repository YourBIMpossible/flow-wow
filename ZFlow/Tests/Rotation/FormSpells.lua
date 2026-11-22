-- Tests for ZFlow/Rotation/FormSpells.lua (S16): which spells take you out
-- of a form. The pure parts are checked against Flow 0.35.377
-- (Modules/Rotation/FormSpells.lua): same window, rules and texts. The
-- client has no form list, spell name or spell tooltip read yet, so the
-- module cases put hand-made ones on the fake client; that is not proof
-- the game gives them. Not tested in game.
local _, ns = ...

local FS = ns.FormSpells
local tests = {}

local CLASS = "DRUID"
local BEAR, CAT = "Bear Form", "Cat Form"
local WRATH, ROAR, BEARFORM = 5176, 99, 5487 -- test values, not client data
local NAMES = { [WRATH] = "Wrath", [ROAR] = "Demoralizing Roar", [BEARFORM] = BEAR }

local function pack()
    return {
        options = { shapeshifts = true },
        spells = {
            ["Maul"] = { level = 10, needs = BEAR },
            ["Claw"] = { level = 20, needs = CAT },
            ["Wrath"] = { level = 1 },
            ["Odd"] = { level = 1, needs = "Stealth" },
        },
    }
end

local function formList()
    return {
        { index = 1, name = BEAR, active = false },
        { index = 2, name = CAT, active = false },
    }
end

-- ------------------------------------------------------------------- pure
tests["form spells: a class shifts only when its pack says so"] = function(t)
    t.eq(FS.Shifts(pack()), true)
    t.eq(FS.Shifts({ options = {} }), false)
    t.eq(FS.Shifts({ options = { shapeshifts = 1 } }), false)
    t.eq(FS.Shifts(nil), false)
end

tests["form spells: a note is news once, and the latest wins"] = function(t)
    local s = {}
    t.eq(FS.Note(s, "Wrath", BEAR, false), true)
    t.eq(FS.Note(s, "Wrath", BEAR, false), false)
    t.eq(s.Wrath.out[BEAR], true)
    t.eq(FS.Note(s, "Wrath", BEAR, true), true)
    t.eq(s.Wrath.keep[BEAR], true)
    t.eq(s.Wrath.out[BEAR], nil)
    t.eq(FS.Note(s, "Wrath", CAT, false), true)
    t.eq(s.Wrath.keep[BEAR], true)
    t.eq(s.Wrath.out[CAT], true)
end

tests["form spells: a note with a missing part is not kept"] = function(t)
    local s = {}
    t.eq(FS.Note(s, nil, BEAR, true), false)
    t.eq(FS.Note(s, "Wrath", nil, true), false)
    t.eq(FS.Note(nil, "Wrath", BEAR, true), false)
    t.eq(next(s), nil)
end

tests["form spells: form abilities come from the needs of the pack"] = function(t)
    local a = FS.FormAbilities(pack())
    t.eq(a.Maul, BEAR)
    t.eq(a.Claw, CAT)
    t.eq(a.Wrath, nil)
    t.eq(a.Odd, nil, "a need that is not a form")
    t.eq(next(FS.FormAbilities(nil)), nil)
end

tests["form spells: the tooltip words are those of Flow, with this title"] = function(t)
    local text, r, g, b = FS.Words({ out = { [BEAR] = true } }, nil, "T")
    t.eq(text, "T: takes you out of Bear Form")
    t.eq(r, 1) t.eq(g, 0.6) t.eq(b, 0.2)
    text, r, g, b = FS.Words({ keep = { [BEAR] = true } }, nil, "T")
    t.eq(text, "T: keeps you in Bear Form")
    t.eq(r, 0.4) t.eq(g, 1) t.eq(b, 0.4)
    text = FS.Words({ out = { [CAT] = true }, keep = { [BEAR] = true } }, nil, "T")
    t.eq(text, "T: takes you out of Cat Form; keeps you in Bear Form")
    text = FS.Words(nil, BEAR, "T")
    t.eq(text, "T: a Bear Form ability (keeps you in it)")
    text, r, g, b = FS.Words(nil, nil, "T")
    t.eq(text, "T: not seen cast in a form yet (learned the first time you do)")
    t.eq(r, 0.6) t.eq(g, 0.6) t.eq(b, 0.6)
end

tests["form spells: what was seen is said before the word of the pack"] = function(t)
    local text = FS.Words({ out = { [BEAR] = true } }, BEAR, "T")
    t.eq(text, "T: takes you out of Bear Form")
    text = FS.Words({ keep = {}, out = {} }, BEAR, "T")
    t.eq(text, "T: a Bear Form ability (keeps you in it)", "an empty record says nothing")
end

tests["form spells: several forms are joined in order"] = function(t)
    local text = FS.Words({ keep = { ["C Form"] = true, ["A Form"] = true, ["B Form"] = true } }, nil, "T")
    t.eq(text, "T: keeps you in A Form, B Form and C Form")
    text = FS.Words({ keep = { ["B Form"] = true, ["A Form"] = true } }, nil, "T")
    t.eq(text, "T: keeps you in A Form and B Form")
end

tests["form spells: the form you are in, from the list and the number"] = function(t)
    local name, known = FS.Current(formList(), 1)
    t.eq(name, BEAR) t.eq(known, true)
    name, known = FS.Current(formList(), 0)
    t.eq(name, nil) t.eq(known, true)
    name, known = FS.Current(nil, 0)
    t.eq(name, nil) t.eq(known, true, "number 0 is no form, list or not")
end

tests["form spells: a form that cannot be named is not known, never no form"] = function(t)
    local name, known = FS.Current(nil, 1)
    t.eq(name, nil) t.eq(known, false)
    name, known = FS.Current(formList(), 3)
    t.eq(name, nil) t.eq(known, false, "a number the list does not have")
    name, known = FS.Current({ { index = 1 } }, 1)
    t.eq(name, nil) t.eq(known, false, "a row with no name")
    name, known = FS.Current(nil, nil)
    t.eq(name, nil) t.eq(known, false)
end

tests["form spells: with no number the marks of the list are used"] = function(t)
    local list = formList()
    list[2].active = true
    local name, known = FS.Current(list, nil)
    t.eq(name, CAT) t.eq(known, true)
    name, known = FS.Current(formList(), nil)
    t.eq(name, nil) t.eq(known, true, "every mark read, none on")
    list = formList()
    list[1].active = nil
    name, known = FS.Current(list, nil)
    t.eq(name, nil) t.eq(known, false, "a mark not read")
    list = formList()
    list[1].active, list[1].name = true, nil
    name, known = FS.Current(list, nil)
    t.eq(name, nil) t.eq(known, false, "the form on has no name")
end

tests["form spells: the spell of a form and the cancel are not learned"] = function(t)
    t.eq(FS.IsFormSpell(formList(), BEAR), true)
    t.eq(FS.IsFormSpell(formList(), "Wrath"), false)
    t.eq(FS.IsFormSpell(nil, FS.CANCEL), true)
    t.eq(FS.IsFormSpell(nil, BEAR), false, "no list: not known to be one")
end

local function watcher()
    local seen = {}
    local w = FS.New(function(spell, form, kept) seen[#seen + 1] = { spell, form, kept } end)
    return w, seen
end

tests["form spells watcher: a cast that leaves you in the form keeps it"] = function(t)
    local w, seen = watcher()
    w.sent("Roar", BEAR, 10)
    w.cast("Roar", BEAR, 10.3)
    t.eq(#seen, 1)
    t.eq(seen[1][1], "Roar") t.eq(seen[1][2], BEAR) t.eq(seen[1][3], true)
    t.eq(w.pending, nil)
end

tests["form spells watcher: the form dropping inside the window is put on the cast"] = function(t)
    local w, seen = watcher()
    w.sent("Wrath", BEAR, 10)
    w.formChanged(BEAR, nil, 10 + FS.WINDOW)
    t.eq(#seen, 1)
    t.eq(seen[1][1], "Wrath") t.eq(seen[1][2], BEAR) t.eq(seen[1][3], false)
    t.eq(w.pending, nil)
    t.eq(w.dropped, nil)
end

tests["form spells watcher: a drop after the window is not put on the cast"] = function(t)
    local w, seen = watcher()
    w.sent("Wrath", BEAR, 10)
    w.formChanged(BEAR, nil, 10 + FS.WINDOW + 0.01)
    t.eq(#seen, 0)
    t.eq(w.dropped.form, BEAR)
end

tests["form spells watcher: the form may drop just before the cast is sent"] = function(t)
    local w, seen = watcher()
    w.formChanged(BEAR, nil, 10)
    w.sent("Wrath", nil, 10.4)
    t.eq(#seen, 1)
    t.eq(seen[1][2], BEAR) t.eq(seen[1][3], false)
    t.eq(w.dropped, nil)
    w.sent("Wrath", nil, 10.5)
    t.eq(#seen, 1, "one drop goes to one spell")
end

tests["form spells watcher: an old drop is not blamed on a later cast"] = function(t)
    local w, seen = watcher()
    w.formChanged(BEAR, nil, 10)
    w.sent("Wrath", nil, 10 + FS.WINDOW + 0.01)
    t.eq(#seen, 0)
    t.eq(w.pending, nil, "a cast in no form is not waited on")
end

tests["form spells watcher: a cast seen too late is dropped, not kept"] = function(t)
    local w, seen = watcher()
    w.sent("Roar", BEAR, 10)
    w.cast("Roar", BEAR, 10 + FS.WINDOW * 4 + 0.01)
    t.eq(#seen, 0)
    t.eq(w.pending, nil)
end

tests["form spells watcher: another spell or another form says nothing"] = function(t)
    local w, seen = watcher()
    w.sent("Roar", BEAR, 10)
    w.cast("Wrath", BEAR, 10.1)
    w.cast("Roar", CAT, 10.2)
    t.eq(#seen, 0)
    t.eq(w.pending.spell, "Roar")
    w.formChanged(CAT, nil, 10.3)
    t.eq(#seen, 0, "a different form dropping")
end

tests["form spells watcher: a change that is none, and forgetting"] = function(t)
    local w, seen = watcher()
    w.formChanged(nil, BEAR, 10)
    w.formChanged(BEAR, BEAR, 10)
    t.eq(w.dropped, nil)
    w.sent("Roar", BEAR, 10)
    w.formChanged(CAT, nil, 10)
    w.forget()
    t.eq(w.pending, nil)
    t.eq(w.dropped, nil)
    w.cast("Roar", BEAR, 10.1)
    t.eq(#seen, 0)
end

tests["form spells: the lines of the word, sorted"] = function(t)
    local lines = FS.Lines({
        Wrath = { out = { [BEAR] = true, [CAT] = true } },
        Roar = { keep = { [BEAR] = true } },
    }, { Maul = BEAR }, "T")
    t.eq(#lines, 4)
    t.eq(lines[1], "forms: what T has seen your spells do (cast one in a form and it is learned)")
    t.eq(lines[2], "  takes you out of the form: Wrath (Bear Form), Wrath (Cat Form)")
    t.eq(lines[3], "  keeps you in it: Roar (Bear Form)")
    t.eq(lines[4], "  form abilities (keep it): Maul (Bear Form)")
end

tests["form spells: the lines with nothing seen"] = function(t)
    local lines = FS.Lines(nil, nil, "T")
    t.eq(#lines, 3)
    t.eq(lines[2], "  takes you out of the form: none seen yet")
    t.eq(lines[3], "  keeps you in it: none seen yet")
end

-- ------------------------------------------------------------- the module
-- opts.forms / opts.names / opts.tooltip = false leaves that read off the
-- client, as it is today.
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    local w = { c = c, list = formList(), added = {} }
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setClass(opts.class or CLASS)
    c.setForm(0)
    if opts.forms ~= false then c.forms = function() return w.list end end
    if opts.names ~= false then c.spellName = function(id) return NAMES[id] end end
    if opts.tooltip ~= false then
        c.onSpellTooltip = function(fn)
            w.hook = fn
            return function() w.hook = nil end
        end
    end
    local k = ns.Kernel({}, c)
    local diag = { commands = {}, help = {} }
    w.k, w.diag = k, diag
    w.api = FS.Declare(k, diag, { [CLASS] = pack(), ROGUE = { options = {}, spells = {} } })
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    function w.shift(n)
        c.setForm(n)
        c.fire("UPDATE_SHAPESHIFT_FORM")
    end
    function w.sent(id, unit) c.fire("UNIT_SPELLCAST_SENT", unit or "player", "Target", "cast-1", id) end
    function w.done(id, unit) c.fire("UNIT_SPELLCAST_SUCCEEDED", unit or "player", "cast-1", id) end
    function w.data() return k.store:table("account", FS.PATH .. "." .. CLASS) end
    function w.tip(spell)
        w.added = {}
        w.hook(spell, function(text, r, g, b) w.added[#w.added + 1] = { text, r, g, b } end)
        return w.added
    end
    return w
end

tests["form spells module: the word and the setting are registered"] = function(t)
    local w = start()
    t.eq(type(w.diag.commands[FS.WORD]), "function")
    t.eq(w.diag.help[FS.WORD], FS.HELP)
    t.eq(w.k.settings:get(FS.SETTING), true)
    t.eq(w.k.problems:count(FS.NAME), 0)
end

tests["form spells module: a cast that leaves you in the form is kept"] = function(t)
    local w = start()
    w.shift(1)
    w.sent(ROAR)
    w.c.advance(0.3)
    w.done(ROAR)
    local r = w.data()["Demoralizing Roar"]
    t.ok(type(r) == "table", "a record")
    t.eq(r.keep[BEAR], true)
    t.eq(r.out, nil)
end

tests["form spells module: a cast that drops the form is learned"] = function(t)
    local w = start()
    w.shift(1)
    w.sent(WRATH)
    w.c.advance(0.2)
    w.shift(0)
    t.eq(w.data().Wrath.out[BEAR], true)
    w.done(WRATH)
    t.eq(w.data().Wrath.keep, nil, "the cast going off in no form keeps nothing")
end

tests["form spells module: the form dropping just before the cast is sent"] = function(t)
    local w = start()
    w.shift(1)
    w.shift(0)
    w.c.advance(0.2)
    w.sent(WRATH)
    t.eq(w.data().Wrath.out[BEAR], true)
end

tests["form spells module: a drop long after the cast is not learned"] = function(t)
    local w = start()
    w.shift(1)
    w.sent(WRATH)
    w.c.advance(FS.WINDOW + 0.5)
    w.shift(0)
    t.eq(w.data().Wrath, nil)
end

tests["form spells module: a cast by another unit is ignored"] = function(t)
    local w = start()
    w.shift(1)
    w.sent(ROAR, "target")
    w.done(ROAR, "target")
    t.eq(w.api.watcher.pending, nil)
    t.eq(next(w.data()), nil)
end

tests["form spells module: shifting into a form is not a spell learned about"] = function(t)
    local w = start()
    w.shift(1)
    w.sent(BEARFORM)
    t.eq(w.api.watcher.pending, nil)
    w.shift(0)
    t.eq(next(w.data()), nil)
end

tests["form spells module: a form that is not known is never read as no form"] = function(t)
    local w = start()
    w.shift(1)
    w.sent(WRATH)
    w.list[1].active, w.list[2].active = nil, nil
    w.shift(nil)
    local form, known = w.api.form()
    t.eq(form, nil) t.eq(known, false)
    t.eq(w.api.watcher.pending, nil, "nothing half seen is kept")
    t.eq(next(w.data()), nil, "not learned as leaving the form")
    w.sent(WRATH)
    t.eq(w.api.watcher.pending, nil, "no cast is watched while it is not known")
    w.shift(0)
    t.eq(next(w.data()), nil, "coming back known is not a form change")
end

tests["form spells module: a spell with no name is not learned"] = function(t)
    local w = start()
    w.shift(1)
    w.sent(424242)
    w.sent(nil)
    t.eq(w.api.watcher.pending, nil)
    t.eq(w.k.problems:count(FS.NAME), 0)
end

tests["form spells module: the setting off stops the watching and the line"] = function(t)
    local w = start()
    w.k.settings:set(FS.SETTING, false)
    w.shift(1)
    w.sent(ROAR)
    w.done(ROAR)
    t.eq(w.api.watcher.pending, nil)
    t.eq(next(w.data()), nil)
    t.eq(w.api.line("Wrath"), nil)
    t.eq(#w.tip("Wrath"), 0)
end

tests["form spells module: a class that does not shift"] = function(t)
    local w = start({ class = "ROGUE" })
    w.shift(1)
    w.sent(ROAR)
    t.eq(w.api.watcher.pending, nil)
    t.eq(w.api.line("Wrath"), nil)
    local lines = w.api.lines()
    t.eq(#lines, 1)
    t.eq(lines[1], "forms: your class does not shift form")
end

tests["form spells module: a class with no pack does not shift"] = function(t)
    local w = start({ class = "MAGE" })
    t.eq(w.api.line("Wrath"), nil)
    t.eq(w.api.lines()[1], "forms: your class does not shift form")
    w.c.setClass(nil)
    t.eq(w.api.line("Wrath"), nil, "class not known")
end

tests["form spells module: the tooltip line"] = function(t)
    local w = start()
    local title = w.k.id.title
    local a = w.tip("Wrath")
    t.eq(#a, 1)
    t.eq(a[1][1], title .. ": not seen cast in a form yet (learned the first time you do)")
    a = w.tip("Maul")
    t.eq(a[1][1], title .. ": a Bear Form ability (keeps you in it)")
    w.shift(1)
    w.sent(WRATH)
    w.shift(0)
    a = w.tip("Wrath")
    t.eq(a[1][1], title .. ": takes you out of Bear Form")
    t.eq(a[1][2], 1) t.eq(a[1][3], 0.6) t.eq(a[1][4], 0.2)
end

tests["form spells module: no tooltip line for a form itself or a spell with no name"] = function(t)
    local w = start()
    t.eq(#w.tip(BEAR), 0)
    t.eq(#w.tip(FS.CANCEL), 0)
    t.eq(#w.tip(nil), 0)
    w.hook("Wrath", nil)
    t.eq(w.k.problems:count(FS.NAME), 0)
end

tests["form spells module: the word prints what was learned"] = function(t)
    local w = start()
    w.shift(1)
    w.sent(WRATH)
    w.shift(0)
    local before = #w.c.printed
    w.diag.commands[FS.WORD]()
    t.eq(#w.c.printed - before, 4)
    local title = w.k.id.title
    t.eq(w.c.printed[before + 1], title .. ": forms: what " .. title
        .. " has seen your spells do (cast one in a form and it is learned)")
    t.eq(w.c.printed[before + 2], "  takes you out of the form: Wrath (Bear Form)")
    t.eq(w.c.printed[before + 3], "  keeps you in it: none seen yet")
    t.eq(w.c.printed[before + 4], "  form abilities (keep it): Claw (Cat Form), Maul (Bear Form)")
end

tests["form spells module: what was learned is kept by class in the account table"] = function(t)
    local w = start()
    w.shift(1)
    w.sent(WRATH)
    w.shift(0)
    local forms = w.k.store:get("account", FS.PATH)
    t.ok(type(forms) == "table" and type(forms[CLASS]) == "table", "facts.forms.<CLASS>")
    t.eq(forms[CLASS].Wrath.out[BEAR], true)
end

-- The client as it is today: none of the three reads.
tests["form spells module: with no form list nothing is learned, and one problem says so"] = function(t)
    local w = start({ forms = false })
    t.eq(w.k.problems:count(FS.NAME), 1, "said at the first look")
    w.shift(1)
    local form, known = w.api.form()
    t.eq(form, nil) t.eq(known, false, "a form number with no list has no name")
    w.sent(WRATH)
    w.shift(0)
    t.eq(w.k.problems:count(FS.NAME), 1, "said once")
    t.eq(w.api.watcher.pending, nil)
    t.eq(next(w.data()), nil)
    form, known = w.api.form()
    t.eq(form, nil) t.eq(known, true, "form number 0 is no form without a list")
end

tests["form spells module: with no spell name read nothing is learned, and one problem says so"] = function(t)
    local w = start({ names = false })
    t.eq(w.k.problems:count(FS.NAME), 0)
    w.shift(1)
    w.sent(WRATH)
    w.sent(ROAR)
    t.eq(w.k.problems:count(FS.NAME), 1)
    t.eq(w.api.watcher.pending, nil)
end

tests["form spells module: with no tooltip hook the word still works, and one problem says so"] = function(t)
    local w = start({ tooltip = false })
    t.eq(w.k.problems:count(FS.NAME), 1)
    t.eq(w.hook, nil)
    w.shift(1)
    w.sent(WRATH)
    w.shift(0)
    t.eq(w.api.lines()[2], "  takes you out of the form: Wrath (Bear Form)")
end

tests["form spells module: a read that raises is a read not known"] = function(t)
    local w = start()
    w.shift(1)
    w.c.forms = function() error("boom") end
    w.sent(WRATH)
    t.eq(w.api.watcher.pending, nil)
    w.shift(0)
    t.eq(next(w.data()), nil)
end

return tests
