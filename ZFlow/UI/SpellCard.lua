local _, ns = ...

-- The new-spell card (G33): when the player learns a spell, a short card
-- with its name and its rank.
--
-- Pure. The learned spell comes in as { name =, rank = }, exactly as the
-- client reported it. Nothing is guessed: no rank from the client means no
-- rank on the card.
--
-- No rotation claim. G33 also asks whether the rotation uses the spell, but
-- the only public rotation read today, ns.RotationReader.SpellNames, is the
-- pack's whole spell catalogue (Hibernate, Aquatic Form, ...), not what the
-- rotation's rules cast. Until Rotation offers that (ROTATION NEED posted
-- with this fix), the card says nothing about the rotation rather than
-- something untrue.
--
-- Lead section 242: the second argument, the class pack, gives a tip line
-- when its spell row has a `tip` (help for a spell that is no rule: Mind
-- Soothe, Mind Control, Levitate). No pack or no tip: no tip line.
--
-- The chat lines are said by Spells/TrainerModule.lua on client.onSpellLearned.
-- Look-only: the card casts, buys and changes nothing.
--
-- The card window (lead section 402 item 5): learning a spell also opens a
-- small kit window (client.kitWindow, the kit's parts only) with the spell,
-- its tip and where it sits: the bar and slot the game put it on
-- (SPELL_PUSHED_TO_ACTIONBAR, kept by Rotation/SpellKeys.lua, or told after
-- the card opened), else one line of advice to put it on a bar. The advice
-- is words: nothing places, binds or casts the spell. The client has no read
-- of what is on the bars, so a spell the player placed by hand is not seen.
-- It follows the card setting (spells.newSpellCard); the player closes it
-- (Escape). One card at a time: the newest spell.
--
--   S.Where(id, placed)       -> the newest slot the game put id in, or nil
--   S.WhereLine(name, slot)   -> the where line, or the bar advice
--   S.Children(card, slot)    -> the window's parts, nil for no card
--   S.Declare(k) -> api       api.Shown()

ns.SpellCard = {}
local S = ns.SpellCard

S.NAME = "spellCard"
S.ID = "SpellCard"
S.HEADER = "New spell"
S.SETTING = "spells.newSpellCard"   -- Spells/TrainerModule.lua's row
S.PUSHED = "SPELL_PUSHED_TO_ACTIONBAR"
S.LIST_PATH = "rotation.placedSpells"  -- Rotation/SpellKeys.lua's list
S.ON_BAR = "On your bars: %s, slot %d (the game put it there)."
S.ON_SLOT = "On your bars, slot %d (the game put it there)."
S.ADVICE = "Put it on a bar: open your spellbook and drag %s to an action bar."

local function text(v)
    if type(v) == "string" and v ~= "" then return v end
    return nil
end

-- { name =, rank = (nil when not known), tip = (nil when none) }, or nil
-- when the learned spell has no name.
function S.Build(learned, pack)
    if type(learned) ~= "table" then return nil end
    local name = text(learned.name)
    if not name then return nil end
    local tip
    local spells = type(pack) == "table" and pack.spells or nil
    local row = type(spells) == "table" and spells[name] or nil
    if type(row) == "table" then tip = text(row.tip) end
    return { name = name, rank = text(learned.rank), tip = tip }
end

-- The card's lines, plain text; {} for no card.
function S.Lines(card)
    if type(card) ~= "table" or not card.name then return {} end
    local first = "New spell: " .. card.name
    if card.rank then first = first .. " (" .. card.rank .. ")" end
    if type(card.tip) == "string" then return { first, "Tip: " .. card.tip } end
    return { first }
end

-- The newest slot the game put spell id in, from a list of { id, slot }.
function S.Where(id, placed)
    if type(id) ~= "number" or type(placed) ~= "table" then return nil end
    for i = #placed, 1, -1 do
        local row = placed[i]
        if type(row) == "table" and row.id == id and type(row.slot) == "number" then return row.slot end
    end
    return nil
end

function S.WhereLine(name, slot)
    if type(slot) == "number" then
        local SK = ns.SpellKeys
        local bar, n
        if type(SK) == "table" and type(SK.BarOf) == "function" then bar, n = SK.BarOf(slot) end
        if bar then return S.ON_BAR:format(bar, n) end
        return S.ON_SLOT:format(slot)
    end
    return S.ADVICE:format(tostring(name))
end

function S.Children(card, slot)
    if type(card) ~= "table" or not card.name then return nil end
    local title = card.name
    if card.rank then title = title .. " (" .. card.rank .. ")" end
    local spell = { kind = "line", key = "spell", text = title }
    if type(card.tip) == "string" then spell.sub = "Tip: " .. card.tip end
    return {
        { kind = "header", key = "header", title = S.HEADER },
        spell,
        { kind = "line", key = "where", text = S.WhereLine(card.name, slot) },
    }
end

local function ask(client, name, ...)
    if type(client) ~= "table" or type(client[name]) ~= "function" then return nil end
    local ok, v = pcall(client[name], ...)
    if not ok then return nil end
    return v
end

function S.Declare(k)
    local api = {}
    local ctx, handle, stopLearned
    local shown = nil   -- { card, id, slot }: the card on screen

    local function problem(id, text)
        if type(k.problems) == "table" then k.problems:add(S.NAME, id, text) end
    end

    local function placed()
        local ok, list = pcall(ctx.store.get, ctx.store, "char", S.LIST_PATH)
        return ok and type(list) == "table" and list or nil
    end

    local function draw()
        local client = ctx.client
        if type(client.kitWindow) ~= "function" or type(ns.Kit) ~= "table" then return end
        local id = k.id or ns.id
        local tree, why = ns.Kit.Window({ id = S.ID, title = id.title .. ": " .. S.HEADER,
            children = S.Children(shown.card, shown.slot) })
        if not tree then
            problem("window", tostring(why))
            return
        end
        if handle then
            handle.update(tree)
        else
            handle = client.kitWindow(S.ID, tree, {
                name = id.framePrefix .. "SpellCard",
                point = tree.point, width = tree.width, height = tree.height,
                onClose = function() end,
                failed = function(err) problem("draw", tostring(err)) end,
            })
            if not handle then
                problem("window", "the client could not draw the card")
                return
            end
        end
        handle.show(true)
    end

    local function learned(spell)
        if not ctx or ctx.settings:get(S.SETTING) ~= true then return end
        local class = ask(ctx.client, "class")
        local pack = type(class) == "string" and type(ns.Packs) == "table" and ns.Packs[class] or nil
        local card = S.Build(spell, pack)
        if not card then return end
        local id = type(spell) == "table" and spell.id or nil
        shown = { card = card, id = id, slot = S.Where(id, placed()) }
        draw()
    end

    function api.Shown()
        return handle ~= nil and type(handle.shown) == "function" and handle.shown() == true
    end

    k:Module({
        name = S.NAME,
        needs = { "client", "store", "settings", "bus" },
        start = function(c)
            ctx = c
            stopLearned = ask(c.client, "onSpellLearned", function(spell)
                local ok, err = pcall(learned, spell)
                if not ok then problem("card", tostring(err)) end
            end)
            c.bus:on(S.NAME, S.PUSHED, function(spellId, slot)
                if shown and shown.id ~= nil and shown.id == spellId and type(slot) == "number" then
                    shown.slot = slot
                    draw()
                end
            end)
        end,
        stop = function()
            if type(stopLearned) == "function" then stopLearned() end
            stopLearned, shown = nil, nil
            if handle then handle.close() end
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.spellCard = S.Declare(ns)
