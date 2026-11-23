local _, ns = ...

-- Group buff tooltip (S17): hover another friendly player and read which of
-- your own group buffs they have. Ported from Flow's
-- Modules/Rotation/Tooltip.lua, text only. It reads and adds lines to the
-- game's unit tooltip; nothing is cast, targeted or clicked.
--
-- Not seen in game: the unit tooltip hook, the reads of the hovered unit and
-- its buffs (Core/Client.lua onUnitTooltip, unitInfo, unitBuff) are first
-- guesses and need a game test. Where the client hides another player's
-- buffs the line says so; a buff not known is never said to be missing.
--
--   text       = GroupTip.Left(seconds)
--   text, tone = GroupTip.Line(spell, up, left, found)
--   kind       = GroupTip.Kind(class, role, power)
--   lines      = GroupTip.Lines(client, pack, unit)
--   api        = GroupTip.Declare(k[, packs])
--     api.hooked()   true once the client's unit tooltip is being followed
--     api.errors()   how many tooltips could not be worked out
--   ns.use(GroupTip.NAME) -> { Hooked = api.hooked, Errors = api.errors }
--
-- A pack names its group buffs in `groupBuffs`, a list of rules:
--   { spell = name, aura = { names that count }, who = "all" | { kinds and classes } }
-- A pack without the list says nothing.

ns.GroupTip = {}
local T = ns.GroupTip

T.NAME = "groupTip"
T.SETTING = "general.groupTip"
T.HEADER = "Your buffs for them:"
T.INDENT = "  "
T.HEADER_COLOUR = { 1, 0.82, 0.25 }
T.COLOUR = {
    has = { 0.45, 1, 0.45 },
    other = { 0.45, 1, 0.45 },
    missing = { 1, 0.35, 0.35 },
    hidden = { 0.7, 0.7, 0.7 },
}

-- Kinds by class, as Flow has them (Modules/Rotation/Engine.lua). A class
-- not listed here has no kind: it is not called melee.
local MELEE = { WARRIOR = true, ROGUE = true, PALADIN = true, DEATHKNIGHT = true }
local CASTER = { MAGE = true, WARLOCK = true, PRIEST = true, SHAMAN = true }

-- The time left, as text after a line: " (4 s)", " (2 min)" from 90 seconds
-- up, or "" for no time worth saying (none, not known, no end).
function T.Left(seconds)
    if type(seconds) ~= "number" or seconds ~= seconds then return "" end
    if seconds <= 0 or seconds == math.huge then return "" end
    if seconds >= 90 then return string.format(" (%d min)", math.floor(seconds / 60 + 0.5)) end
    return string.format(" (%d s)", math.floor(seconds + 0.5))
end

-- One line for one buff. up: true (they have it), false (read, and they do
-- not), nil (not known). found: the name of the buff they have, where it is
-- another one that counts.
function T.Line(spell, up, left, found)
    spell = tostring(spell)
    if up == true then
        if type(found) == "string" and found ~= spell then
            return string.format("%s: has %s%s", spell, found, T.Left(left)), "other"
        end
        return string.format("%s: has it%s", spell, T.Left(left)), "has"
    end
    if up == false then return spell .. ": MISSING", "missing" end
    return spell .. ": can't tell (the game hides their buffs)", "hidden"
end

-- What a player is to a buff: "tank", "healer", "melee", "caster", "ranged",
-- or nil for not known. The role chosen in the group comes first; a druid
-- goes by the power bar (1 rage: bear, 3 energy: cat, anything else read:
-- caster; not read: not known).
function T.Kind(class, role, power)
    if type(class) ~= "string" then return nil end
    if role == "TANK" then return "tank" end
    if role == "HEALER" then return "healer" end
    if class == "HUNTER" then return "ranged" end
    if class == "DRUID" then
        if type(power) ~= "number" then return nil end
        if power == 1 then return "tank" end
        if power == 3 then return "melee" end
        return "caster"
    end
    if MELEE[class] then return "melee" end
    if CASTER[class] then return "caster" end
    return nil
end

-- Is this rule for that player? "all", or a list holding their kind or class.
local function fits(who, kind, class)
    if who == "all" then return true end
    if type(who) ~= "table" then return false end
    for i = 1, #who do
        if (kind ~= nil and who[i] == kind) or (class ~= nil and who[i] == class) then return true end
    end
    return false
end

-- The lines for one hovered unit: { { text, tone } ... } in the order of
-- the pack, or nil when there is nothing to say (not another friendly
-- player, or no rule of yours fits). Each of exists, player, isSelf and
-- friendly has to be known: a unit not known to be friendly gets nothing.
function T.Lines(client, pack, unit)
    if type(client) ~= "table" or type(pack) ~= "table" or type(unit) ~= "string" then return nil end
    local rules = pack.groupBuffs
    if type(rules) ~= "table" or type(client.unitInfo) ~= "function" then return nil end
    local info = client.unitInfo(unit)
    if type(info) ~= "table" then return nil end
    if info.exists ~= true or info.player ~= true or info.isSelf ~= false or info.friendly ~= true then
        return nil
    end
    local class = type(info.class) == "string" and info.class or nil
    local kind = T.Kind(class, info.role, info.power)
    local lines = {}
    for i = 1, #rules do
        local rule = rules[i]
        if type(rule) == "table" and type(rule.spell) == "string" and fits(rule.who, kind, class) then
            local id = client.spellId(rule.spell)
            local spell = id ~= nil and client.spell(id) or nil
            if type(spell) == "table" and spell.known == true then
                local names = {}
                if type(rule.aura) == "table" then
                    for j = 1, #rule.aura do names[j] = rule.aura[j] end
                else
                    names[1] = rule.spell
                end
                local up, left, found
                if type(client.unitBuff) == "function" then
                    up, left, found = client.unitBuff(unit, names)
                end
                local text, tone = T.Line(rule.spell, up, left, found)
                lines[#lines + 1] = { text = text, tone = tone }
            end
        end
    end
    if #lines == 0 then return nil end
    return lines
end

function T.Declare(k, packs)
    local api = {}
    local hooked, errors, cancel = false, 0, nil
    local seen = {}
    function api.hooked() return hooked end
    function api.errors() return errors end

    k:Module({
        name = T.NAME,
        needs = { "client", "store", "bus" },
        settings = { {
            key = T.SETTING, scope = "account", type = "bool", default = true,
            label = "Your buffs on a player's tooltip",
            help = "Hover another friendly player to read which of your group buffs they have. It casts nothing.",
            group = "party", synonyms = { "buffs", "group", "party", "raid", "tooltip" },
        } },
        provides = { Hooked = api.hooked, Errors = api.errors },
        start = function(ctx)
            local client = ctx.client
            local got
            if type(client.onUnitTooltip) == "function" then
                got = client.onUnitTooltip(function(unit, add)
                    if ctx.settings:get(T.SETTING) ~= true or type(add) ~= "function" then return end
                    -- Every line is worked out before the first is added, so
                    -- an error leaves the tooltip as the game made it.
                    local ok, lines = pcall(function()
                        local class = client.class()
                        local all = packs or ns.Packs
                        local pack = type(class) == "string" and type(all) == "table" and all[class] or nil
                        return T.Lines(client, pack, unit)
                    end)
                    if not ok then
                        errors = errors + 1
                        local text = tostring(lines)
                        if not seen[text] then
                            seen[text] = true
                            k.problems:add(T.NAME, "tooltip", text)
                        end
                        return
                    end
                    if type(lines) ~= "table" or #lines == 0 then return end
                    add(T.HEADER, T.HEADER_COLOUR[1], T.HEADER_COLOUR[2], T.HEADER_COLOUR[3])
                    for i = 1, #lines do
                        local colour = T.COLOUR[lines[i].tone] or T.COLOUR.hidden
                        add(T.INDENT .. lines[i].text, colour[1], colour[2], colour[3])
                    end
                end)
            end
            if type(got) == "function" then
                cancel, hooked = got, true
            else
                -- Said once, in the report: the tooltip stays as the game made it.
                k.problems:add(T.NAME, "read", "this client does not offer the unit tooltip")
            end
        end,
        stop = function()
            if cancel then cancel() end
            cancel, hooked = nil, false
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.groupTip = T.Declare(ns)
