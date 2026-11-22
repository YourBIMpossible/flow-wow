local _, ns = ...

-- Which spells take you out of a form. The game does not say it of a
-- spell, so this watches what happens: you cast a spell in Bear Form and
-- are still in Bear Form after, the spell keeps that form; the form drops
-- as you cast it, the spell takes you out of it. A form's own abilities
-- (the class pack's spells with `needs = "Bear Form"`) keep it from the
-- start. A spell's tooltip then says which, and the `forms` word lists all.
--
-- A port of Flow 0.35.377 Modules/Rotation/FormSpells.lua: same window,
-- same rules, same texts (with this addon's title). Kept for the whole
-- account by class at facts.forms.<CLASS>: game facts only, a class, a
-- spell name and a form name. Only for a class whose pack says
-- options.shapeshifts = true.
--
-- It only watches and writes text: nothing is cast, shifted or pressed.
--
-- The client reads it needs are not in Core/Client.lua yet, so each is
-- asked for only if the client has it, and one problem line says what is
-- missing (see RESEARCH-form-spells.md for their shape):
--   client.forms()            -> { { index, name, active } ... } or nil
--   client.spellName(id)      -> the spell's name or nil
--   client.onSpellTooltip(fn) -> cancel;  fn(name, add);  add(text, r, g, b)
-- client.form() (the form's number, 0 for none) is there already.
--
-- Pure:
--   FS.Note(store, spell, form, kept) -> true when it is news
--   FS.FormAbilities(pack)            -> { [spell] = form }
--   FS.Words(rec, ability, title)     -> text, r, g, b
--   FS.Current(forms, index)          -> form name or nil, known (true/false)
--   FS.IsFormSpell(forms, spell)      -> true for a form's own spell
--   FS.Lines(store, abilities, title) -> the lines of the `forms` word
--   FS.New(note)                      -> watcher: sent / formChanged / cast / forget
-- Not tested in game.

local FS = {}
ns.FormSpells = FS

FS.NAME = "formSpells"
FS.SETTING = "rotation.formSpells"
FS.PATH = "facts.forms"
FS.WORD = "forms"
FS.HELP = "what your spells have been seen to do to your form"
FS.WINDOW = 1.0            -- seconds between a cast and its form dropping that belong together
FS.CANCEL = "Cancel Form"  -- not a spell that is learned about (as in Flow)

function FS.Shifts(pack)
    return type(pack) == "table" and type(pack.options) == "table" and pack.options.shapeshifts == true
end

-- Notes what a cast did. store: { [spell] = { keep = { [form] = true },
-- out = { [form] = true } } }. kept: still in the form after it.
function FS.Note(store, spell, form, kept)
    if not (type(store) == "table" and type(spell) == "string" and type(form) == "string") then return false end
    local r = store[spell]
    if type(r) ~= "table" then
        r = {}
        store[spell] = r
    end
    local side = kept and "keep" or "out"
    if type(r[side]) ~= "table" then r[side] = {} end
    if r[side][form] then return false end
    r[side][form] = true
    -- Seen both ways in one form: the latest wins; the game can change.
    local other = kept and "out" or "keep"
    if type(r[other]) == "table" then r[other][form] = nil end
    return true
end

-- The form abilities of a class pack: { [spell] = form } (Maul = Bear Form).
function FS.FormAbilities(pack)
    local out = {}
    if type(pack) ~= "table" or type(pack.spells) ~= "table" then return out end
    for spell, s in pairs(pack.spells) do
        if type(spell) == "string" and type(s) == "table" and type(s.needs) == "string"
            and s.needs:find(" Form$") then
            out[spell] = s.needs
        end
    end
    return out
end

local function names(set)
    local list = {}
    for f in pairs(type(set) == "table" and set or {}) do list[#list + 1] = f end
    table.sort(list)
    if #list <= 1 then return list[1] end
    return table.concat(list, ", ", 1, #list - 1) .. " and " .. list[#list]
end

-- What a spell's tooltip says. rec: its record (or nil); ability: the form
-- it belongs to (or nil); title: the addon's name as shown.
function FS.Words(rec, ability, title)
    title = tostring(title or "")
    local keep = type(rec) == "table" and names(rec.keep) or nil
    local out = type(rec) == "table" and names(rec.out) or nil
    if out and keep then
        return string.format("%s: takes you out of %s; keeps you in %s", title, out, keep), 1, 0.6, 0.2
    end
    if out then return string.format("%s: takes you out of %s", title, out), 1, 0.6, 0.2 end
    if keep then return string.format("%s: keeps you in %s", title, keep), 0.4, 1, 0.4 end
    if ability then return string.format("%s: a %s ability (keeps you in it)", title, ability), 0.4, 1, 0.4 end
    return string.format("%s: not seen cast in a form yet (learned the first time you do)", title), 0.6, 0.6, 0.6
end

-- The form you are in, from the client's form list and form number.
-- -> name, true   in that form
-- -> nil, true    in no form
-- -> nil, false   not known: never read as "no form"
function FS.Current(forms, index)
    if index == 0 then return nil, true end
    if type(forms) ~= "table" then return nil, false end
    if type(index) == "number" then
        for i = 1, #forms do
            local f = forms[i]
            if type(f) == "table" and f.index == index then
                if type(f.name) == "string" then return f.name, true end
                return nil, false
            end
        end
        return nil, false
    end
    -- No form number: the list's own active marks, only when every one is read.
    local found
    for i = 1, #forms do
        local f = forms[i]
        if type(f) ~= "table" or type(f.active) ~= "boolean" then return nil, false end
        if f.active then
            if type(f.name) ~= "string" then return nil, false end
            found = found or f.name
        end
    end
    return found, true
end

function FS.IsFormSpell(forms, spell)
    if spell == FS.CANCEL then return true end
    for i = 1, #(type(forms) == "table" and forms or {}) do
        local f = forms[i]
        if type(f) == "table" and f.name == spell then return true end
    end
    return false
end

-- The watcher. note(spell, form, kept) is called for each thing seen.
-- Times are seconds on one clock; forms are names, nil for no form.
function FS.New(note)
    local w = { pending = nil, dropped = nil }
    -- A cast was sent: the form you are in now.
    function w.sent(spell, form, now)
        if type(spell) ~= "string" or type(now) ~= "number" then return end
        -- The form may already have dropped as the cast went out.
        if not form and w.dropped and now - w.dropped.at <= FS.WINDOW then
            note(spell, w.dropped.form, false)
            w.dropped = nil
            return
        end
        if form then w.pending = { spell = spell, form = form, at = now } end
    end
    -- Your form changed from `from` to `to`.
    function w.formChanged(from, to, now)
        if not from or from == to or type(now) ~= "number" then return end
        local p = w.pending
        if p and p.form == from and now - p.at <= FS.WINDOW then
            note(p.spell, from, false)
            w.pending = nil
            return
        end
        w.dropped = { form = from, at = now }
    end
    -- A cast began or went off: the form you are in now.
    function w.cast(spell, form, now)
        local p = w.pending
        if not (p and p.spell == spell) or type(now) ~= "number" then return end
        if now - p.at > FS.WINDOW * 4 then
            w.pending = nil
            return
        end
        if form == p.form then
            note(spell, form, true)
            w.pending = nil
        end
    end
    -- The form stopped being known: nothing half seen is kept.
    function w.forget()
        w.pending, w.dropped = nil, nil
    end
    return w
end

local function pairsOf(t) return pairs(type(t) == "table" and t or {}) end

-- The lines of the `forms` word.
function FS.Lines(store, abilities, title)
    local keep, out = {}, {}
    for spell, r in pairsOf(store) do
        if type(spell) == "string" and type(r) == "table" then
            for form in pairsOf(r.out) do out[#out + 1] = spell .. " (" .. form .. ")" end
            for form in pairsOf(r.keep) do keep[#keep + 1] = spell .. " (" .. form .. ")" end
        end
    end
    table.sort(keep)
    table.sort(out)
    local lines = { string.format("forms: what %s has seen your spells do (cast one in a form and it is learned)",
        tostring(title or "")) }
    lines[#lines + 1] = "  takes you out of the form: " .. (#out > 0 and table.concat(out, ", ") or "none seen yet")
    lines[#lines + 1] = "  keeps you in it: " .. (#keep > 0 and table.concat(keep, ", ") or "none seen yet")
    local abil = {}
    for spell, form in pairsOf(abilities) do abil[#abil + 1] = spell .. " (" .. form .. ")" end
    table.sort(abil)
    if #abil > 0 then lines[#lines + 1] = "  form abilities (keep it): " .. table.concat(abil, ", ") end
    return lines
end

-- --------------------------------------------------------------- the module
function FS.Declare(k, diag, packs)
    local client
    local api = {}
    local formNow, formKnown = nil, false
    local said = {}

    local function read(fn, ...)
        if type(fn) ~= "function" then return nil end
        local ok, v = pcall(fn, ...)
        if ok then return v end
        return nil
    end
    local function missing(what, text)
        if said[what] then return end
        said[what] = true
        k.problems:add(FS.NAME, what, text)
    end

    local function pack()
        local class = client and read(client.class) or nil
        local all = packs or ns.Packs
        if type(class) ~= "string" or type(all) ~= "table" then return nil, nil end
        return all[class], class
    end
    -- Your class's record, the store's own table (a change is saved as it
    -- is made). Asked for at each use: it is not there before the client
    -- has loaded the saved table.
    local function store(class)
        if type(class) ~= "string" or class == "" or class:find(".", 1, true) then return nil end
        return k.store:table("account", FS.PATH .. "." .. class)
    end
    local function on()
        if not client or k.settings:get(FS.SETTING) == false then return false end
        return FS.Shifts((pack()))
    end
    local function forms()
        if type(client.forms) ~= "function" then
            missing("forms", "the client has no form list read (client.forms): forms are not learned")
            return nil
        end
        return read(client.forms)
    end
    local function current(list)
        return FS.Current(list, read(client.form))
    end
    local function spellOf(id)
        if type(client.spellName) ~= "function" then
            missing("spellName", "the client has no spell name read (client.spellName): forms are not learned")
            return nil
        end
        local name = type(id) == "number" and read(client.spellName, id) or nil
        return type(name) == "string" and name or nil
    end
    local function now()
        local t = read(client.now)
        return type(t) == "number" and t or nil
    end

    local watcher = FS.New(function(spell, form, kept)
        local _, class = pack()
        local data = store(class)
        if data then FS.Note(data, spell, form, kept) end
    end)
    api.watcher = watcher

    -- The line for one of your spells: text, r, g, b; nil for a form spell
    -- itself, a class that does not shift, or the setting off.
    function api.line(spell)
        if type(spell) ~= "string" or not on() then return nil end
        local p, class = pack()
        local list = type(client.forms) == "function" and read(client.forms) or nil
        if FS.IsFormSpell(list, spell) then return nil end
        local data = store(class) or {}
        return FS.Words(data[spell], FS.FormAbilities(p)[spell], k.id.title)
    end
    function api.lines()
        local p, class = pack()
        if not FS.Shifts(p) then return { "forms: your class does not shift form" } end
        return FS.Lines(store(class), FS.FormAbilities(p), k.id.title)
    end
    function api.form() return formNow, formKnown end

    local function seeForm()
        if not on() then return end
        local f, known = current(forms())
        if not known then
            formNow, formKnown = nil, false
            watcher.forget()
            return
        end
        local t = now()
        if formKnown and f ~= formNow and t then watcher.formChanged(formNow, f, t) end
        formNow, formKnown = f, true
    end
    local function sent(unit, _, _, id)
        if unit ~= "player" or not on() then return end
        local spell, t = spellOf(id), now()
        if not spell or not t then return end
        local list = forms()
        local f, known = current(list)
        if not known or FS.IsFormSpell(list, spell) then return end
        watcher.sent(spell, f, t)
    end
    local function cast(unit, _, id)
        if unit ~= "player" or not on() or not watcher.pending then return end
        local spell, t = spellOf(id), now()
        if not spell or not t then return end
        local f, known = current(forms())
        if known then watcher.cast(spell, f, t) end
    end

    local function run()
        if not client then return end
        local lines = api.lines()
        for i = 1, #lines do client.print(i == 1 and (k.id.title .. ": " .. lines[i]) or lines[i]) end
    end

    k:Module({
        name = FS.NAME,
        needs = { "client", "store" },
        settings = { {
            key = FS.SETTING, scope = "account", type = "bool", default = true,
            label = "Learn which spells break your form",
            help = "Watches your own casts and says on a spell's tooltip whether it keeps your form. It casts nothing.",
            group = "Rotation",
        } },
        start = function(ctx)
            client = ctx.client
            client.listen("PLAYER_LOGIN", seeForm)
            client.listen("PLAYER_ENTERING_WORLD", seeForm)
            client.listen("UPDATE_SHAPESHIFT_FORM", seeForm)
            client.listen("UNIT_SPELLCAST_SENT", sent)
            client.listen("UNIT_SPELLCAST_START", cast)
            client.listen("UNIT_SPELLCAST_SUCCEEDED", cast)
            if type(client.onSpellTooltip) ~= "function" then
                missing("tooltip", "the client has no spell tooltip hook (client.onSpellTooltip): no tooltip line")
                return
            end
            client.onSpellTooltip(function(spell, add)
                if type(add) ~= "function" then return end
                -- The line is worked out before it is added, so an error
                -- leaves the tooltip as the game made it.
                local ok, text, r, g, b = pcall(api.line, spell)
                if not ok then
                    missing("line", tostring(text))
                    return
                end
                if text then add(text, r, g, b) end
            end)
        end,
    })

    if diag and type(diag.commands) == "table" then
        diag.commands[FS.WORD] = run
        if type(diag.help) == "table" then diag.help[FS.WORD] = FS.HELP end
    end

    return api
end

-- The addon's own.
ns.formSpells = FS.Declare(ns, ns.diag)
