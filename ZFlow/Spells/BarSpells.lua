local _, ns = ...

-- Spells to put on the action bars (parity C-48, Flow Builtins.lua:179-210).
-- A spell the class pack casts (its lists, in order, then its heals) that
-- the player knows and that is on no action bar or the stance bar is an
-- advisor line "Put Frostbolt on your action bars: Z-Flow will suggest it".
-- Look-only: nothing is placed on a bar.
--
--   rows = B.Missing(pack, known, on, skip)
--     known(name) -> true when known; on = client.actionSpells() ({[name] = slot},
--     nil when not read: then nil, never "on no bar"); skip = {[name] = true}.
--     rows = { { spell, why = "Rotation" | "Survival" }, ... }
--
-- Flow leaves out a spell NewSpell covers (muted, or given its own key). Here:
-- a spell the player chose to skip (Rotation/SpellKeys.lua choices, "skip").
--
-- Setting (char, on by default): spells.barAdvice "Spells on your bars".

local B = {}
ns.SpellBars = B

B.NAME = "spellBars"
B.SETTING = "spells.barAdvice"
B.PROMPT = "spells.bars."
B.PRIORITY = 2
B.CHOICES = "rotation.spellChoices"
B.TEXT = "Put %s on your action bars: %s will suggest it"

local function sortedKeys(t)
    local keys = {}
    for k in pairs(t) do if type(k) == "string" then keys[#keys + 1] = k end end
    table.sort(keys)
    return keys
end

function B.Missing(pack, known, on, skip)
    if type(on) ~= "table" then return nil end
    if type(pack) ~= "table" or type(known) ~= "function" then return {} end
    skip = type(skip) == "table" and skip or {}
    local out, seen = {}, {}
    local function consider(spell, why)
        if type(spell) ~= "string" or seen[spell] then return end
        seen[spell] = true
        local ok, k = pcall(known, spell)
        if ok and k == true and on[spell] == nil and not skip[spell] then
            out[#out + 1] = { spell = spell, why = why }
        end
    end
    local lists = type(pack.lists) == "table" and pack.lists or {}
    local order = {}
    if type(lists.default) == "table" then order[1] = lists.default end
    for _, name in ipairs(sortedKeys(lists)) do
        if name ~= "default" and type(lists[name]) == "table" then order[#order + 1] = lists[name] end
    end
    for _, list in ipairs(order) do
        for _, rule in ipairs(list) do
            if type(rule) == "table" then consider(rule.spell, "Rotation") end
        end
    end
    local heals = type(pack.heals) == "table" and pack.heals or {}
    for _, key in ipairs({ "self", "hots" }) do
        if type(heals[key]) == "table" then
            for _, spell in ipairs(heals[key]) do consider(spell, "Survival") end
        end
    end
    return out
end

function B.Text(spell)
    return string.format(B.TEXT, spell, ns.id.title)
end

function B.Declare(k)
    k:Module({
        name = B.NAME,
        needs = { "client", "store", "bus", "settings", "advisor" },
        settings = {
            { key = B.SETTING, scope = "char", type = "bool", default = true,
              label = "Spells on your bars",
              help = "Say which spells you know that the rotation uses but are on no action bar. It places nothing.",
              group = "combat.spells", synonyms = { "action bars", "bars", "missing spells" } },
        },
        start = function(ctx)
            local advisor = ctx.use("advisor")
            local shown = {}

            local function known(name)
                local id = ctx.client.spellId(name)
                if type(id) ~= "number" then return nil end
                local row = ctx.client.spell(id)
                return type(row) == "table" and row.known == true
            end

            local function skips()
                local out = {}
                local choices = ctx.store:get("char", B.CHOICES)
                if type(choices) == "table" then
                    for name, v in pairs(choices) do if v == "skip" then out[name] = true end end
                end
                return out
            end

            local function refresh()
                local ok, err = pcall(function()
                    local rows
                    if ctx.settings:get(B.SETTING) == true then
                        local class = ctx.client.class()
                        local pack = type(ns.Packs) == "table" and type(class) == "string" and ns.Packs[class] or nil
                        rows = B.Missing(pack, known, ctx.client.actionSpells(), skips())
                    end
                    local want = {}
                    for _, r in ipairs(rows or {}) do want[B.PROMPT .. r.spell] = B.Text(r.spell) end
                    for id in pairs(shown) do
                        if not want[id] then advisor.Remove(id); shown[id] = nil end
                    end
                    for _, r in ipairs(rows or {}) do
                        local id = B.PROMPT .. r.spell
                        if not shown[id] and advisor.Add(id, want[id], B.PRIORITY) then shown[id] = true end
                    end
                end)
                if not ok then k.problems:add("spells", "bar spells", tostring(err)) end
            end

            ctx.bus:on(B.NAME, "ACTIONBAR_SLOT_CHANGED", refresh)
            ctx.bus:on(B.NAME, "UPDATE_SHAPESHIFT_FORMS", refresh)
            ctx.bus:on(B.NAME, "SPELLS_CHANGED", refresh)
            ctx.bus:on(B.NAME, "LEARNED_SPELL_IN_TAB", refresh)
            ctx.bus:on(B.NAME, "PLAYER_LEVEL_UP", refresh)
            refresh()
        end,
    })
end

-- The addon's own: declared when this file loads, started at login.
B.Declare(ns)
