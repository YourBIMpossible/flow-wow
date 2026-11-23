local _, ns = ...

-- The seal and the blessing you put up yourself, and the ones you choose
-- with a word (CF-32, N12; lead sections 226 to 228).
--
-- Your casts. It watches your own casts that went off
-- (UNIT_SPELLCAST_SUCCEEDED, unit "player"). A cast whose name matches a
-- row of your class pack's options.sticky is kept:
--   * for this fight, in memory, until the fight ends (PLAYER_REGEN_ENABLED);
--   * and, when no word has chosen one for that row, for the role you play
--     (the setting spec.role; none chosen counts as dps), saved for the
--     character, until you cast another for that role.
-- A row with onYou = true (a blessing, which can go on someone else) is
-- kept only once it lands on you: your own buffs (client.ownBuffs) show it
-- new or renewed within OC.WINDOW seconds of the cast, read on UNIT_AURA
-- for you. The buffs before the cast are read at UNIT_SPELLCAST_SENT, else
-- at the cast. Never seen landing: dropped.
--
-- The words. For each row with `word` (seal, blessing), `<slash> <word>
-- <name>` chooses one of the row's `names` for the character (short names:
-- crusader, kings); `auto` clears the choice; anything else lists the
-- names. Choosing (or auto) forgets the ones you cast for that row, for
-- every role, and this fight's.
--
--   options.sticky = { { prefix = "Seal of ", key = "seal", word = "seal",
--                        names = { "Seal of Righteousness", ... } },
--                      { prefix = "Blessing of ", key = "blessing",
--                        only = { ["Blessing of Kings"] = true, ... },
--                        onYou = true, word = "blessing", names = { ... } } }
--
-- Saved for the character: state.ownCasts[role][key] = name (your casts)
-- and state.ownChoice[key] = name (the words). Spell names only.
--
-- What the rotation gets (snapshot.chosen), for the role you play now:
--   [key]            the one you cast for this role
--   [key .. "Set"]   the word's choice
--   [key .. "Fight"] the one you cast this fight
-- The class pack decides which counts first. It only watches, keeps names
-- and prints: nothing is cast, pressed or set.
--
-- Client reads, each asked in a pcall; a read not given or not answered
-- keeps nothing, never a guess: class, spellName, ownBuffs, now, spellId,
-- spell; lines go out through print.
--
-- Pure:
--   OC.Match(rows, name)         -> the first row the name matches, or nil
--   OC.Note(rows, name)          -> that row's key, or nil
--   OC.Role(role)                -> the role a cast is kept under
--   OC.Find(names, prefix, text) -> the name a short name means, or nil
--   OC.Short(names, prefix)      -> the short names, ", " between
--   OC.Landed(before, after)     -> true when a blessing landed on you
-- Module (ns.use("ownCasts")):
--   Chosen()                     -> the map above, or nil when it holds nothing
-- Not tested in game.

local OC = {}
ns.OwnCasts = OC

OC.NAME = "ownCasts"
OC.PATH = "state.ownCasts"     -- [role] = { [key] = name }
OC.CHOICE = "state.ownChoice"  -- [key] = name
OC.ROLE = "spec.role"
OC.ROLES = { "dps", "heal", "tank" }
OC.DEFAULT_ROLE = "dps"        -- none chosen: the old add-on's usual role
OC.WINDOW = 3                  -- seconds from a cast to its buff showing on you
OC.UNREAD = {}                 -- your buffs could not be read
OC.EVENT = "UNIT_SPELLCAST_SUCCEEDED"   -- unit, castGUID, spellID
OC.SENT = "UNIT_SPELLCAST_SENT"         -- unit, target, castGUID, spellID
OC.AURA = "UNIT_AURA"                   -- unit
OC.FIGHT_END = "PLAYER_REGEN_ENABLED"
-- PC-7: the line said when a cast becomes the kept seal or blessing.
OC.SAY = "rotation.sayKept"
-- PC-1: the driver, for what it picks and suggests now.
OC.DRIVER = "rotationDriver"
-- PC-7: the role in the player's words (Rotation/Role.lua's words).
OC.ROLE_WORDS = { dps = "damage", heal = "healing", tank = "tanking" }

local IS_ROLE = {}
for _, role in ipairs(OC.ROLES) do IS_ROLE[role] = true end

-- A name matches a row that starts it with the row's prefix (and has more
-- after it), and, when the row has `only`, is in that set.
function OC.Match(rows, name)
    if type(rows) ~= "table" or type(name) ~= "string" then return nil end
    for _, row in ipairs(rows) do
        if type(row) == "table" and type(row.prefix) == "string" and row.prefix ~= ""
            and type(row.key) == "string" and row.key ~= ""
            and #name > #row.prefix and string.sub(name, 1, #row.prefix) == row.prefix
            and (row.only == nil or (type(row.only) == "table" and row.only[name] == true)) then
            return row
        end
    end
    return nil
end

function OC.Note(rows, name)
    local row = OC.Match(rows, name)
    return row and row.key or nil
end

function OC.Role(role)
    if type(role) == "string" and IS_ROLE[role] then return role end
    return OC.DEFAULT_ROLE
end

-- A name in lower case without the prefix and a leading "the ".
local function bare(name, prefix)
    local text = string.lower(name)
    local p = string.lower(type(prefix) == "string" and prefix or "")
    if p ~= "" and string.sub(text, 1, #p) == p then text = string.sub(text, #p + 1) end
    text = (string.gsub(text, "^the%s+", ""))
    return text
end

local function trim(text)
    return (string.gsub(text, "^%s*(.-)%s*$", "%1"))
end

function OC.Find(names, prefix, text)
    if type(names) ~= "table" or type(text) ~= "string" then return nil end
    local want = bare(trim(text), prefix)
    if want == "" then return nil end
    for _, name in ipairs(names) do
        if type(name) == "string" and string.find(bare(name, prefix), want, 1, true) == 1 then return name end
    end
    return nil
end

function OC.Short(names, prefix)
    local out = {}
    for _, name in ipairs(type(names) == "table" and names or {}) do
        if type(name) == "string" then out[#out + 1] = bare(name, prefix) end
    end
    return table.concat(out, ", ")
end

-- PC-1 (legacy keptFromCast, Classes/Paladin/Rotation.lua:62-66 at
-- origin/program-integ): a cast of the one the rotation would put up right
-- now is not a choice of yours. view: the driver's last view. true when the
-- name is what row.pick(view.snapshot) gives, or the spell it suggests;
-- false when it is not, or it cannot be told (no view, no pick, a pick
-- that raises): then the cast is kept, as before.
function OC.Fresh(row, view, name)
    if type(row) ~= "table" or type(view) ~= "table" or type(name) ~= "string" then return false end
    local suggestion = view.suggestion
    if type(suggestion) == "table" and suggestion.spell == name then return true end
    if type(row.pick) == "function" and type(view.snapshot) == "table" then
        local ok, picked = pcall(row.pick, view.snapshot)
        if ok and picked == name then return true end
    end
    return false
end

-- PC-7 (legacy Rotation.lua:138-139, 257-258): the line said when a cast
-- becomes the one kept for your role. No name of yours in it.
function OC.Line(row, name, roleWord, slash)
    local word = type(row) == "table" and tostring(row.word or row.key or "") or ""
    return string.format("%s: kept up while you play %s. Cast another to switch; %s %s auto: back to your role's.",
        tostring(name), tostring(roleWord), tostring(slash), word)
end

-- before: the buff's time left on you before the cast (nil: not up;
-- OC.UNREAD: not read); after: now. New, or renewed by more than a second.
function OC.Landed(before, after)
    if before == OC.UNREAD then return false end
    if after == nil or after == false then return false end
    if before == nil then return true end
    if type(before) == "number" and type(after) == "number" then return after > before + 1 end
    return false
end

function OC.Declare(k, diag, packs)
    local client
    local api = {}
    local fight = {}           -- [key] = name, this fight's casts
    local sentRec, pending     -- a blessing being cast / waiting to land on you

    local function read(fn, ...)
        if type(fn) ~= "function" then return nil end
        local ok, v = pcall(fn, ...)
        if ok then return v end
        return nil
    end

    local function allPacks()
        local all = packs or ns.Packs
        return type(all) == "table" and all or {}
    end
    local function rows()
        local class = client and read(client.class) or nil
        if type(class) ~= "string" then return nil end
        local pack = allPacks()[class]
        local options = type(pack) == "table" and pack.options or nil
        local sticky = type(options) == "table" and options.sticky or nil
        return type(sticky) == "table" and sticky or nil
    end
    local function rowFor(word)
        for _, row in ipairs(rows() or {}) do
            if type(row) == "table" and row.word == word then return row end
        end
        return nil
    end

    local function role()
        local ok, v = pcall(k.settings.get, k.settings, OC.ROLE)
        return OC.Role(ok and v or nil)
    end
    local function now()
        local t = client and read(client.now) or nil
        return type(t) == "number" and t or nil
    end
    local function choiceOf(key)
        local v = k.store:get("char", OC.CHOICE .. "." .. key)
        return type(v) == "string" and v or nil
    end

    -- What is kept for the role you play now, the words' choices and this
    -- fight's casts; nil when there is nothing.
    function api.chosen()
        local out, any = {}, false
        local function put(key, name)
            if type(key) == "string" and type(name) == "string" then
                out[key] = name
                any = true
            end
        end
        local mine = k.store:get("char", OC.PATH .. "." .. role())
        if type(mine) == "table" then
            for key, name in pairs(mine) do put(key, name) end
        end
        local choice = k.store:get("char", OC.CHOICE)
        if type(choice) == "table" then
            for key, name in pairs(choice) do
                if type(key) == "string" then put(key .. "Set", name) end
            end
        end
        for key, name in pairs(fight) do put(key .. "Fight", name) end
        return any and out or nil
    end

    local function say(line)
        local c = client or k.client
        if type(c) == "table" and type(c.print) == "function" then c.print(k.id.title .. ": " .. line) end
    end

    -- PC-7: the line is on unless the setting is read as off.
    local function sayOn()
        local ok, v = pcall(k.settings.get, k.settings, OC.SAY)
        return not (ok and v == false)
    end

    -- PC-1: the driver's last view, or nil.
    local function driverView()
        if type(k.use) ~= "function" then return nil end
        local ok, driver = pcall(k.use, OC.DRIVER)
        if not ok or type(driver) ~= "table" or type(driver.View) ~= "function" then return nil end
        local asked, view = pcall(driver.View)
        if asked and type(view) == "table" then return view end
        return nil
    end

    -- A cast taken: for this fight, and for the role unless a word chose.
    -- PC-7: a change of the one kept for the role is said in one line.
    local function accept(row, name)
        local key = row.key
        fight[key] = name
        if choiceOf(key) ~= nil then return end
        local r = role()
        local path = OC.PATH .. "." .. r .. "." .. key
        local was = k.store:get("char", path)
        k.store:set("char", path, name)
        if was ~= name and sayOn() then say(OC.Line(row, name, OC.ROLE_WORDS[r] or r, k.id.slash)) end
    end

    local function nameOf(id)
        if type(id) ~= "number" or not client then return nil end
        local name = read(client.spellName, id)
        return type(name) == "string" and name or nil
    end
    local function ownBuff(name)
        local buffs = client and read(client.ownBuffs) or nil
        if type(buffs) ~= "table" then return OC.UNREAD end
        return buffs[name]
    end

    -- A blessing waiting to land: kept when your buffs show it, dropped
    -- after OC.WINDOW seconds or when the time cannot be read.
    local function check()
        if not pending then return end
        local t = now()
        if not t or not pending.at or t - pending.at > OC.WINDOW then
            pending = nil
            return
        end
        local after = ownBuff(pending.name)
        if after == OC.UNREAD then return end
        if OC.Landed(pending.before, after) then
            local p = pending
            pending = nil
            accept(p.row, p.name)
        end
    end

    local function sent(unit, _, _, id)
        if unit ~= "player" then return end
        local name = nameOf(id)
        local row = name and OC.Match(rows(), name) or nil
        if not (row and row.onYou) then
            sentRec = nil
            return
        end
        sentRec = { name = name, before = ownBuff(name), at = now() }
    end

    local function cast(unit, _, id)
        if unit ~= "player" then return end
        local name = nameOf(id)
        local row = name and OC.Match(rows(), name) or nil
        if not row then return end
        local s = sentRec
        sentRec = nil
        -- PC-1: the one picked or suggested when you cast it: not your choice.
        if OC.Fresh(row, driverView(), name) then return end
        if not row.onYou then
            accept(row, name)
            return
        end
        -- PC-5: the buffs before the cast are the ones read at
        -- UNIT_SPELLCAST_SENT; an aura that came between SENT and this
        -- event is then seen by the check below.
        local t = now()
        local fromSent = s ~= nil and s.name == name and t ~= nil and s.at ~= nil and t - s.at <= OC.WINDOW
        local before
        if fromSent then before = s.before else before = ownBuff(name) end
        pending = { key = row.key, row = row, name = name, at = t, before = before }
        if fromSent then check() end
    end

    local function aura(unit)
        if unit == "player" then check() end
    end

    -- ------------------------------------------------------------ the words

    -- true / false as the client says you know it; nil when not read.
    local function knownNow(name)
        local id = client and read(client.spellId, name) or nil
        if type(id) ~= "number" then return nil end
        local row = read(client.spell, id)
        if type(row) == "table" and type(row.known) == "boolean" then return row.known end
        return nil
    end

    local function setChoice(key, name)
        k.store:set("char", OC.CHOICE .. "." .. key, name)
        for _, r in ipairs(OC.ROLES) do
            if type(k.store:get("char", OC.PATH .. "." .. r)) == "table" then
                k.store:set("char", OC.PATH .. "." .. r .. "." .. key, nil)
            end
        end
        fight[key] = nil
        if pending and pending.key == key then pending = nil end
    end

    function api.run(word, rest)
        local row = rowFor(word)
        if not row then
            say(word .. ": your class has none to choose.")
            return
        end
        local names = type(row.names) == "table" and row.names or {}
        local usage = string.format("Say %s %s %s, or auto.", tostring(k.id.slash), word, OC.Short(names, row.prefix))
        local text = trim(string.lower(tostring(rest or "")))
        if text == "" then
            local was = choiceOf(row.key)
            say(word .. ": " .. (was and (was .. ", chosen by you") or "automatic") .. ". " .. usage)
            return
        end
        if text == "auto" then
            setChoice(row.key, nil)
            say(word .. ": automatic again: the one for your role, or one you cast yourself.")
            return
        end
        local name = OC.Find(names, row.prefix, text)
        if not name then
            say(string.format("no %s called '%s'. %s", word, text, usage))
            return
        end
        setChoice(row.key, name)
        local known = knownNow(name)
        local note = ""
        if known == false then
            note = " You don't know it yet: the usual one holds until you do."
        elseif known == nil then
            note = " Not known whether you know it: the usual one holds until it is."
        end
        say(string.format("%s: %s is suggested from now on.%s", word, name, note))
    end

    -- Every word a class pack's sticky rows name, once.
    local function words()
        local out, seen = {}, {}
        for _, pack in pairs(allPacks()) do
            local options = type(pack) == "table" and pack.options or nil
            local sticky = type(options) == "table" and options.sticky or nil
            for _, row in ipairs(type(sticky) == "table" and sticky or {}) do
                if type(row) == "table" and type(row.word) == "string" and row.word ~= "" and not seen[row.word] then
                    seen[row.word] = true
                    out[#out + 1] = row.word
                end
            end
        end
        table.sort(out)
        return out
    end

    k:Module({
        name = OC.NAME,
        needs = { "client", "store" },
        provides = { Chosen = api.chosen },
        -- PC-7: on by default: the old add-on always said it.
        settings = { {
            key = OC.SAY, scope = "account", type = "bool", default = true,
            label = "Say when a seal or blessing you cast is kept",
            help = "One line in chat when a seal or blessing you cast becomes the one suggested for your role. It casts nothing.",
            group = "buffs", synonyms = { "seal", "blessing", "kept", "paladin" },
        } },
        start = function(ctx)
            client = ctx.client
            client.listen(OC.SENT, sent)
            client.listen(OC.EVENT, cast)
            client.listen(OC.AURA, aura)
            client.listen(OC.FIGHT_END, function() fight = {} end)
            if diag and type(diag.commands) == "table" then
                for _, w in ipairs(words()) do
                    if diag.commands[w] == nil then
                        diag.commands[w] = function(rest) api.run(w, rest) end
                        if type(diag.help) == "table" then
                            diag.help[w] = "choose the " .. w .. " kept up: a name, or auto"
                        end
                    end
                end
            end
        end,
    })

    return api
end

-- The addon's own.
ns.ownCasts = OC.Declare(ns, ns.diag)
