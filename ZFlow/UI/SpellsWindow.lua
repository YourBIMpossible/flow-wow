local _, ns = ...

-- The Spells window, the keys that cast a spell, and the "put it on your
-- bars" advice (KNOW lane: C-56, C-58, C-48). One window on the shared kit
-- (UI/Kit.lua) listing the class spells you know that are on no action bar
-- and under no key, and the spells you learned this session.
--
--   the spells word      opens the window. A row for each spell says where
--                        it is: on your bars, under a key that casts it,
--                        skipped, or on no bar. Skip stops the reminder for
--                        that spell (Ask again brings it back).
--   a new spell          learned out of a fight, and not a higher rank of
--                        one you have: the window opens with it at the top
--                        (setting spells.openList).
--   the spellkeys word   lists the keys that cast a spell directly, not
--                        from a bar (the game's key window does not list
--                        them).
--   advice               "Put Moonfire on your action bars", for up to
--                        W.MAX_ADVICE class spells you know that are on no
--                        bar, under no key and not skipped (setting
--                        spells.barAdvice).
--
-- LOOK ONLY in this part: nothing is placed, bound, cast or clicked.
--
-- Client reads: class, spellId, spell, bindingKeys, inCombat, now,
-- onSpellLearned, kitWindow, and actionSpells() -> { [spell name] = slot }
-- or nil. actionSpells is asked for in the lane report (the lead writes
-- Core/Client.lua); while the client has no such read, where a spell sits
-- is "not known": the rows say so and no advice is given.
--
-- Pure parts:
--   W.State(name, bars, keys, skipped) -> "bar" | "key" | "skipped" |
--                                         "none" | "unknown"
--   W.Label(title, state, keys)        the row's words
--   W.Advice(names, bars, keyFor, skipped) -> { { id, text } }
--   W.KeyLines(names, keyFor)          the spellkeys word's lines
--
-- Saved data: char "spells.skipped" = { [spell name] = true }; account
-- "layout.spellsWindow" (where the window stands).

local W = {}
ns.SpellsWindow = W

W.NAME = "spellsWindow"
W.ID = "spells"
W.WORD = "spells"
W.KEYS_WORD = "spellkeys"
W.HEADER = "Spells"
W.PATH = "layout.spellsWindow"
W.SKIPPED = "spells.skipped"
W.SETTING_OPEN = "spells.openList"
W.SETTING_ADVICE = "spells.barAdvice"
W.WIDTH, W.HEIGHT = 460, 420
W.PREFIX = "aps.bars."
W.PRIORITY = 1
W.MAX_ADVICE = 3
-- Seconds between two reads of the bars for a bar change.
W.GAP = 1

W.HELP = "open the spells list: which of your spells are on no bar or key"
W.KEYS_HELP = "list the keys that cast a spell directly, not from a bar"
W.ABOUT = { "Your class spells that are on no action bar and under no key.",
    "Drag a spell from your spellbook onto a bar, or press Skip to stop the reminder for it." }
W.NEW = "Learned this session"
W.REST = "On no bar and no key"
W.NONE = { "No spell is waiting for a place.",
    "A spell you learn shows here, and so does a class spell that is on no bar." }
W.SKIP, W.ASK = "Skip", "Ask again"
W.FOOTER = "Type %s %s for the keys that cast a spell directly."
W.ADVICE = "Put %s on your action bars"
W.KEYS_HEAD = "keys that cast a spell directly (not from a bar):"
W.KEYS_NONE = "no key casts a spell directly: they all go through your bars."
W.KEYS_UNREAD = "the key bindings could not be read."

W.TEXT = {
    bar = "%s: on your bars",
    key = "%s: the key %s casts it",
    skipped = "%s: skipped, no reminder",
    none = "%s: on no bar",
    unknown = "%s: your bars could not be read",
}

function W.State(name, bars, keys, skipped)
    if type(bars) == "table" and bars[name] ~= nil then return "bar" end
    if type(keys) == "table" and #keys > 0 then return "key" end
    if type(skipped) == "table" and skipped[name] == true then return "skipped" end
    if type(bars) ~= "table" then return "unknown" end
    return "none"
end

function W.Label(title, state, keys)
    local form = W.TEXT[state] or W.TEXT.unknown
    if state == "key" then return form:format(title, table.concat(keys, ", ")) end
    return form:format(title)
end

-- names: the spells known, in order. keyFor(name) -> the list of keys.
function W.Advice(names, bars, keyFor, skipped)
    local out = {}
    if type(bars) ~= "table" then return out end
    for _, name in ipairs(type(names) == "table" and names or {}) do
        if #out < W.MAX_ADVICE and W.State(name, bars, keyFor(name), skipped) == "none" then
            out[#out + 1] = { id = W.PREFIX .. name, text = W.ADVICE:format(name) }
        end
    end
    return out
end

function W.KeyLines(names, keyFor)
    local rows = {}
    for _, name in ipairs(type(names) == "table" and names or {}) do
        for _, key in ipairs(keyFor(name) or {}) do
            rows[#rows + 1] = { key = key, name = name }
        end
    end
    table.sort(rows, function(a, b)
        if a.key ~= b.key then return a.key < b.key end
        return a.name < b.name
    end)
    local out = {}
    for i, r in ipairs(rows) do out[i] = "  " .. r.key .. ": " .. r.name end
    return out
end

function W.Declare(k, diag)
    local api = {}
    local ctx, handle, advisor, stopLearned
    local render
    local id = k.id or ns.id
    -- The spells learned this session, newest first: { name, title }.
    local fresh = {}
    local shown = {}
    local lastRead

    local function client() return ctx and ctx.client or k.client end
    local function store() return ctx and ctx.store or k.store end

    local function ask(read, ...)
        local c = client()
        if type(c) ~= "table" or type(c[read]) ~= "function" then return nil end
        local ok, v = pcall(c[read], ...)
        if not ok then return nil end
        return v
    end

    local function keyFor(name)
        local keys = ask("bindingKeys", "SPELL " .. name)
        if type(keys) ~= "table" then return {} end
        return keys
    end

    local function skipped()
        local s = store()
        if type(s) ~= "table" then return {} end
        local ok, v = pcall(s.get, s, "char", W.SKIPPED)
        if ok and type(v) == "table" then return v end
        return {}
    end

    -- The class spells the client says are known, a to z.
    local function knownNames()
        local out = {}
        local class = ask("class")
        local pack
        if type(class) == "string" and type(ns.Packs) == "table" then pack = ns.Packs[class] end
        if type(pack) ~= "table" or type(pack.spells) ~= "table" then return out end
        for name in pairs(pack.spells) do
            if type(name) == "string" then
                local spellId = ask("spellId", name)
                local s
                if type(spellId) == "number" then s = ask("spell", spellId) end
                if type(s) == "table" and s.known == true then out[#out + 1] = name end
            end
        end
        table.sort(out)
        return out
    end

    local function setSkipped(name, on)
        local s = store()
        if type(s) ~= "table" then return end
        local now = {}
        for key, v in pairs(skipped()) do now[key] = v end
        if on then now[name] = true else now[name] = nil end
        local ok, err = s:set("char", W.SKIPPED, now)
        if not ok then k.problems:add(W.NAME, "skip", tostring(err)) end
    end

    local function refreshAdvice()
        if type(advisor) ~= "table" then return end
        local want = {}
        if ctx and ctx.settings:get(W.SETTING_ADVICE) ~= false then
            want = W.Advice(knownNames(), ask("actionSpells"), keyFor, skipped())
        end
        local now = {}
        for _, p in ipairs(want) do
            now[p.id] = true
            advisor.Add(p.id, p.text, W.PRIORITY)
        end
        for old in pairs(shown) do
            if not now[old] then advisor.Remove(old) end
        end
        shown = now
        lastRead = tonumber(ask("now"))
    end

    local function rowOf(name, title, bars, skip)
        local keys = keyFor(name)
        local state = W.State(name, bars, keys, skip)
        local text = W.SKIP
        if state == "skipped" then text = W.ASK end
        return state, { kind = "row", key = "row." .. name, label = W.Label(title, state, keys),
            control = { kind = "button", key = "skip." .. name, text = text, onClick = function()
                setSkipped(name, state ~= "skipped")
                refreshAdvice()
                render()
            end } }
    end

    local function tree()
        local children = {
            { kind = "header", key = "header", title = W.HEADER },
            { kind = "line", key = "about", text = W.ABOUT[1], sub = W.ABOUT[2], wrap = true },
        }
        local bars, skip = ask("actionSpells"), skipped()
        local body, listed = {}, {}
        if #fresh > 0 then
            body[#body + 1] = { kind = "section", key = "new", text = W.NEW }
            for _, f in ipairs(fresh) do
                if not listed[f.name] then
                    listed[f.name] = true
                    local _, row = rowOf(f.name, f.title, bars, skip)
                    body[#body + 1] = row
                end
            end
        end
        local rest = {}
        for _, name in ipairs(knownNames()) do
            if not listed[name] then
                local state, row = rowOf(name, name, bars, skip)
                if state ~= "bar" and state ~= "key" then rest[#rest + 1] = row end
            end
        end
        if #rest > 0 then
            body[#body + 1] = { kind = "section", key = "rest", text = W.REST }
            for _, row in ipairs(rest) do body[#body + 1] = row end
        end
        if #body == 0 then
            body[#body + 1] = { kind = "empty", key = "empty", text = W.NONE[1], how = W.NONE[2] }
        end
        children[#children + 1] = { kind = "scroll", key = "body", children = body }
        children[#children + 1] = { kind = "footer", key = "footer",
            text = W.FOOTER:format(id.slash, W.KEYS_WORD), buttons = api.footerButtons(render) }
        return ns.Kit.Window({ id = W.ID, title = id.title .. ": " .. W.HEADER, resizable = true,
            width = W.WIDTH, height = W.HEIGHT, children = children })
    end

    -- The footer's buttons: none in the look-only part.
    function api.footerButtons() return nil end

    render = function()
        if not handle then return end
        local t, why = tree()
        if not t then
            k.problems:add(W.NAME, "tree", tostring(why))
            return
        end
        handle.update(t)
    end

    function api.Open()
        local c = client()
        if type(c) ~= "table" or type(c.kitWindow) ~= "function" then return false end
        local t, why = tree()
        if not t then
            k.problems:add(W.NAME, "tree", tostring(why))
            return false
        end
        if not handle then
            local point, width, height = ns.Kit.Place(k.store:get("account", W.PATH), t)
            handle = c.kitWindow(W.ID, t, {
                name = id.framePrefix .. "SpellsWindow",
                point = point, width = width, height = height,
                onMoved = function(at, w, h)
                    if type(at) ~= "table" then return end
                    local ok, err = k.store:set("account", W.PATH,
                        { point = { at[1], at[2], at[3], at[4] }, width = w, height = h })
                    if not ok then k.problems:add(W.NAME, "place", tostring(err)) end
                end,
                onClose = function() end,
                failed = function(err) k.problems:add(W.NAME, "draw", tostring(err)) end,
            })
            if not handle then
                k.problems:add(W.NAME, "window", "the client could not draw the window")
                return false
            end
        else
            handle.update(t)
        end
        handle.show(true)
        return true
    end

    function api.Close()
        if handle then handle.close() end
    end

    function api.Shown()
        return handle ~= nil and handle.shown() == true
    end

    -- The names the keys word asks about: the class spells known and the
    -- spells learned this session.
    function api.KeyLines()
        local names, seen = {}, {}
        for _, name in ipairs(knownNames()) do
            names[#names + 1] = name
            seen[name] = true
        end
        for _, f in ipairs(fresh) do
            if not seen[f.name] then
                names[#names + 1] = f.name
                seen[f.name] = true
            end
        end
        return W.KeyLines(names, keyFor)
    end

    function api.Fresh()
        local out = {}
        for i, f in ipairs(fresh) do out[i] = f.name end
        return out
    end

    -- A higher rank of a spell is no new spell: "Rank 2" and up say so.
    local function higherRank(rank)
        if type(rank) ~= "string" then return false end
        local n = tonumber(rank:match("(%d+)"))
        return n ~= nil and n > 1
    end

    local function learned(spell)
        local name
        if type(spell) == "table" then name = spell.name end
        if type(name) == "string" and name ~= "" and not higherRank(spell.rank) then
            for i = #fresh, 1, -1 do
                if fresh[i].name == name then table.remove(fresh, i) end
            end
            local title = name
            if type(spell.rank) == "string" and spell.rank ~= "" then title = name .. " (" .. spell.rank .. ")" end
            table.insert(fresh, 1, { name = name, title = title })
            if ctx and ctx.settings:get(W.SETTING_OPEN) ~= false and ask("inCombat") == false then
                api.Open()
            end
        end
        refreshAdvice()
        render()
    end

    if diag and type(diag.commands) == "table" then
        diag.commands[W.WORD] = function() api.Open() end
        diag.commands[W.KEYS_WORD] = function()
            local c = client()
            if type(c) ~= "table" then return end
            if type(c.bindingKeys) ~= "function" then
                c.print(id.title .. ": " .. W.KEYS_UNREAD)
                return
            end
            local lines = api.KeyLines()
            if #lines == 0 then
                c.print(id.title .. ": " .. W.KEYS_NONE)
                return
            end
            c.print(id.title .. ": " .. W.KEYS_HEAD)
            for i = 1, #lines do c.print(lines[i]) end
        end
        if type(diag.help) == "table" then
            diag.help[W.WORD] = W.HELP
            diag.help[W.KEYS_WORD] = W.KEYS_HELP
        end
    end

    k:Module({
        name = W.NAME,
        needs = { "client", "store", "bus", "settings", "advisor" },
        settings = {
            { key = W.SETTING_OPEN, scope = "char", type = "bool", default = true,
              label = "Open the spells list for a new spell",
              help = "When you learn a new spell out of a fight, open the spells list with it at the top. "
                  .. "A higher rank of a spell you have does not open it.",
              group = "combat.spells", synonyms = { "spell", "new", "learned", "list", "window" } },
            { key = W.SETTING_ADVICE, scope = "char", type = "bool", default = true,
              label = "Remind me of spells on no bar",
              help = "Says which class spells you know are on no action bar and under no key. Skip in the "
                  .. "spells list stops it for one spell.",
              group = "combat.spells", synonyms = { "bar", "action bar", "spell", "reminder", "key" } },
        },
        provides = { Open = api.Open, Close = api.Close, Shown = api.Shown, KeyLines = api.KeyLines,
                     Fresh = api.Fresh },
        start = function(c)
            ctx = c
            advisor = c.use("advisor")
            local function changed()
                refreshAdvice()
                render()
            end
            for _, ev in ipairs({ "PLAYER_LEVEL_UP", "UPDATE_BINDINGS", "PLAYER_REGEN_ENABLED" }) do
                c.bus:on(W.NAME, ev, changed)
            end
            -- A bar or spellbook change comes in bursts: the bars are read
            -- again at most once in W.GAP seconds.
            for _, ev in ipairs({ "ACTIONBAR_SLOT_CHANGED", "SPELLS_CHANGED" }) do
                c.bus:on(W.NAME, ev, function()
                    local now = tonumber(ask("now"))
                    if now ~= nil and lastRead ~= nil and now - lastRead < W.GAP then return end
                    changed()
                end)
            end
            stopLearned = ask("onSpellLearned", learned)
            refreshAdvice()
        end,
        stop = function()
            if type(stopLearned) == "function" then stopLearned() end
            stopLearned = nil
            if handle then handle.close() end
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.spellsWindow = W.Declare(ns, ns.diag)
