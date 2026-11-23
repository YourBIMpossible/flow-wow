-- Tests for ZFlow/Rotation/Role.lua (G31, T-E): the role the player chose,
-- and a reminder when the rotation is playing another one, or has no part
-- for it. Nothing is read from talents: what the rotation plays you as is
-- taken only from the driver's view, and stays not known when the view does
-- not say. Not tested in game.
local _, ns = ...

local Ro = ns.RotationRole
local D = ns.RotationDriver
local tests = {}

local CLASS = "TESTCLASS"

-- A hand-written pack: two roles named, no healing part.
local function pack()
    return {
        roles = {
            dps = { name = "Claws", evidence = "test" },
            tank = { name = "Hide", evidence = "test" },
        },
        spells = {},
        lists = { default = {} },
    }
end

local function joined(lines) return table.concat(lines, "\n") end

-- ------------------------------------------------------------------ names
tests["role: names"] = function(t)
    t.eq(Ro.NAME, "rotationRole")
    t.eq(Ro.SETTING, "spec.role")
    t.eq(Ro.WORD, "role")
    t.eq(Ro.NONE, "")
    t.eq(Ro.CHOICES, { "", "dps", "heal", "tank" })
    t.eq(type(Ro.HELP), "string")
end

-- ------------------------------------------------------------------ check
tests["role: nothing chosen is no reminder"] = function(t)
    local c = Ro.Check("", pack(), "dps")
    t.eq(c.state, "none")
    t.eq(Ro.Reminder(c), nil)
end

tests["role: a value that is no role counts as nothing chosen"] = function(t)
    t.eq(Ro.Check(nil, pack(), "dps").state, "none")
    t.eq(Ro.Check("healer", pack(), "dps").state, "none")
    t.eq(Ro.Check(3, pack(), "dps").state, "none")
end

tests["role: the same role is no reminder"] = function(t)
    local c = Ro.Check("tank", pack(), "tank")
    t.eq(c.state, "same")
    t.eq(c.chosen, "tank")
    t.eq(c.played, "tank")
    t.eq(Ro.Reminder(c), nil)
end

tests["role: another role is a reminder naming both"] = function(t)
    local c = Ro.Check("tank", pack(), "dps")
    t.eq(c.state, "differs")
    t.eq(c.chosen, "tank")
    t.eq(c.played, "dps")
    local text = Ro.Reminder(c)
    t.ok(type(text) == "string" and text:find("tanking", 1, true), "names the chosen role")
    t.ok(text:find("damage", 1, true), "names the role played")
    t.ok(text:find("Claws", 1, true), "names the pack's own name of the role played")
end

tests["role: what the rotation plays is not known: no reminder, and it says so"] = function(t)
    local c = Ro.Check("tank", pack(), nil)
    t.eq(c.state, "unknown")
    t.eq(c.played, nil)
    t.eq(Ro.Reminder(c), nil)
    t.ok(joined(Ro.Lines(c)):find("not known", 1, true))
end

tests["role: a played value that is no role is not known, never a guess"] = function(t)
    t.eq(Ro.Check("tank", pack(), "bear").state, "unknown")
    t.eq(Ro.Check("tank", pack(), true).state, "unknown")
end

tests["role: a role the pack has no part for is a reminder"] = function(t)
    local c = Ro.Check("heal", pack(), nil)
    t.eq(c.state, "noPart")
    local text = Ro.Reminder(c)
    t.ok(type(text) == "string" and text:find("healing", 1, true))
    t.ok(text:find("no healing part", 1, true))
end

tests["role: no part wins over a played role"] = function(t)
    t.eq(Ro.Check("heal", pack(), "dps").state, "noPart")
end

tests["role: a pack that names no roles has no part for any"] = function(t)
    local p = pack()
    p.roles = {}
    t.eq(Ro.Check("dps", p, nil).state, "noPart")
    p.roles = nil
    t.eq(Ro.Check("dps", p, nil).state, "noPart")
end

tests["role: no pack for the class: no reminder"] = function(t)
    local c = Ro.Check("tank", nil, nil)
    t.eq(c.state, "noPack")
    t.eq(Ro.Reminder(c), nil)
    t.ok(joined(Ro.Lines(c)):find("no rotation", 1, true))
end

tests["role: the lines for each state"] = function(t)
    t.ok(joined(Ro.Lines(Ro.Check("", pack(), nil))):find("no role chosen", 1, true))
    local same = joined(Ro.Lines(Ro.Check("tank", pack(), "tank")))
    t.ok(same:find("tanking", 1, true))
    t.ok(same:find("Hide", 1, true), "the pack's name for the chosen role")
    t.ok(same:find("the same", 1, true))
    local differs = Ro.Check("tank", pack(), "dps")
    t.eq(Ro.Lines(differs)[1], Ro.Reminder(differs))
    local noPart = Ro.Check("heal", pack(), nil)
    t.eq(Ro.Lines(noPart)[1], Ro.Reminder(noPart))
end

tests["role: no text spells the old name"] = function(t)
    local all = {}
    for _, chosen in ipairs({ "", "dps", "heal", "tank" }) do
        for _, played in ipairs({ "none", "dps", "tank" }) do
            local c = Ro.Check(chosen, pack(), played ~= "none" and played or nil)
            all[#all + 1] = joined(Ro.Lines(c))
        end
    end
    all[#all + 1] = joined(Ro.Lines(Ro.Check("tank", nil, nil)))
    all[#all + 1] = Ro.HELP
    t.eq(joined(all):find("Flow", 1, true), nil)
end

-- ----------------------------------------------------------------- module
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setDead(false)
    c.setClass(opts.class or CLASS)
    local k = ns.Kernel({}, c)
    local diag = ns.Diag.Start(k)
    diag.help = diag.help or {}
    D.Declare(k, { [CLASS] = pack() })
    local api = Ro.Declare(k, diag, { [CLASS] = pack() })
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c, api, diag
end

local function view(role) return { pack = true, snapshot = { role = role } } end

local function said(c, text)
    local n = 0
    for _, line in ipairs(c.printed) do
        if line:find(text, 1, true) then n = n + 1 end
    end
    return n
end

tests["role module: the setting is a choice, nothing chosen at first"] = function(t)
    local k = start()
    local row = k.settings:row(Ro.SETTING)
    t.eq(row.type, "choice")
    t.eq(row.scope, "char")
    t.eq(row.default, "")
    t.eq(row.choices, { "", "dps", "heal", "tank" })
    t.eq(row.group, "combat.rotation")
    t.eq(k.settings:get(Ro.SETTING), "")
end

tests["role module: nothing chosen says nothing"] = function(t)
    local k, c = start()
    local before = #c.printed
    k.bus:emit(D.EVENT, view("dps"))
    t.eq(#c.printed, before)
end

tests["role module: a role the rotation does not play is said once"] = function(t)
    local k, c = start()
    k.settings:set(Ro.SETTING, "tank")
    k.bus:emit(D.EVENT, view("dps"))
    k.bus:emit(D.EVENT, view("dps"))
    k.bus:emit(D.EVENT, view("dps"))
    t.eq(said(c, "tanking"), 1)
    t.ok(c.printed[#c.printed]:find(ns.id.title, 1, true), "the line carries the title")
end

tests["role module: said again only after it changed"] = function(t)
    local k, c = start()
    k.settings:set(Ro.SETTING, "tank")
    k.bus:emit(D.EVENT, view("dps"))
    k.bus:emit(D.EVENT, view("tank"))
    t.eq(said(c, "tanking"), 1, "the same role: nothing new said")
    k.bus:emit(D.EVENT, view("dps"))
    t.eq(said(c, "tanking"), 2)
end

tests["role module: a view that names no role says nothing"] = function(t)
    local k, c = start()
    k.settings:set(Ro.SETTING, "tank")
    local before = #c.printed
    k.bus:emit(D.EVENT, view(nil))
    k.bus:emit(D.EVENT, { pack = true })
    k.bus:emit(D.EVENT, nil)
    t.eq(#c.printed, before)
end

tests["role module: a role with no part is said once, with the rotation on"] = function(t)
    local k, c = start()
    k.settings:set(Ro.SETTING, "heal")
    k.bus:emit(D.EVENT, view(nil))
    k.bus:emit(D.EVENT, view(nil))
    t.eq(said(c, "no healing part"), 1)
end

tests["role module: the status is the last check"] = function(t)
    local k, _, api = start()
    t.eq(api.status().state, "none")
    k.settings:set(Ro.SETTING, "tank")
    k.bus:emit(D.EVENT, view("dps"))
    t.eq(api.status().state, "differs")
    k.bus:emit(D.EVENT, nil)
    t.eq(api.status().state, "unknown", "the rotation is off: what it plays is not known")
end

tests["role module: no pack for the class says nothing"] = function(t)
    local k, c, api = start({ class = "OTHERCLASS" })
    k.settings:set(Ro.SETTING, "tank")
    local before = #c.printed
    k.bus:emit(D.EVENT, { pack = false, trace = {}, why = { pack = false } })
    t.eq(#c.printed, before)
    t.eq(api.status().state, "noPack")
end

tests["role module: the slash word shows the state"] = function(t)
    local k, c, _, diag = start()
    t.eq(type(diag.commands[Ro.WORD]), "function")
    t.eq(diag.help[Ro.WORD], Ro.HELP)
    diag.commands[Ro.WORD]("")
    t.eq(said(c, "no role chosen"), 1)
    k.settings:set(Ro.SETTING, "tank")
    diag.commands[Ro.WORD]("")
    t.eq(said(c, "not known"), 1)
end

tests["role module: the slash word sets the role"] = function(t)
    local k, _, _, diag = start()
    diag.commands[Ro.WORD]("tank")
    t.eq(k.settings:get(Ro.SETTING), "tank")
    diag.commands[Ro.WORD]("  HEAL ")
    t.eq(k.settings:get(Ro.SETTING), "heal")
    diag.commands[Ro.WORD]("none")
    t.eq(k.settings:get(Ro.SETTING), "")
end

tests["role module: a word that is no role changes nothing and says which words there are"] = function(t)
    local k, c, _, diag = start()
    k.settings:set(Ro.SETTING, "tank")
    diag.commands[Ro.WORD]("bear")
    t.eq(k.settings:get(Ro.SETTING), "tank")
    t.eq(said(c, "dps, heal, tank or none"), 1)
end

tests["role module: it changes no setting but its own"] = function(t)
    local k, _, _, diag = start()
    local was = k.settings:get(D.SETTING)
    t.eq(was, true, "the rotation is on by default (lead section 294)")
    diag.commands[Ro.WORD]("tank")
    k.bus:emit(D.EVENT, view("dps"))
    t.eq(k.settings:get(D.SETTING), was, "the rotation stays as it was")
    k.settings:set(D.SETTING, false)
    diag.commands[Ro.WORD]("heal")
    t.eq(k.settings:get(D.SETTING), false, "a saved off stays off too")
end

-- ------------------------------------------------------------ settings model
tests["role: the settings model has the row"] = function(t)
    local model = ns.Settings.Model.Default()
    local row = model:row("spec.role")
    t.ok(row ~= nil, "the row is there")
    t.eq(row.type, "string")
    t.eq(row.default, "")
    t.eq(model:get({ spec = { role = "tank" } }, "spec.role"), "tank")
    t.eq(model:get({}, "spec.role"), "")
end

return tests
