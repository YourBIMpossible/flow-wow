local _, ns = ...

-- Talent points (parity C-61, C-49). While the player has unspent talent
-- points and is out of combat, the advisor has one prompt, "Spend 3 talent
-- points"; at 0 points it is gone. The first time a character at the
-- talent level is seen with points (a login at level 10 or above), chat
-- says once "talents unlocked: you have 3 talent points to spend." The
-- level-up to 10 itself is said by Rotation/Spec.lua; this module only
-- keeps for the character that it was said, so a reload or a later login
-- never says it again. Look-only: no talent is learned.
--
--   n    = Tl.Unspent(client)   -- points, or nil when not read
--   text = Tl.Text(n)           -- "Spend 1 talent point" / "Spend N talent points"
--
-- Client read: unspentTalents() -> a count, or nil when not known. First
-- guess: UnitCharacterPoints("player") first return. Until the client has
-- the read, nothing is said and no prompt is made (nothing is guessed).
-- inCombat() nil (not known) is not "out of combat": no prompt.
--
-- Setting (char, on by default): spells.talentAdvice "Talent points".

local Tl = {}
ns.SpellTalents = Tl

Tl.NAME = "spellTalents"
Tl.SETTING = "spells.talentAdvice"
Tl.PROMPT = "aps.talents.spend"
Tl.PRIORITY = 3
-- The level the first talent point comes at (as Rotation/Spec.lua).
Tl.LEVEL = 10
Tl.SAID = "spells.talentsUnlockedSaid"
Tl.TEXT_ONE = "Spend 1 talent point"
Tl.TEXT_MANY = "Spend %d talent points"
Tl.UNLOCKED_ONE = "talents unlocked: you have 1 talent point to spend."
Tl.UNLOCKED_MANY = "talents unlocked: you have %d talent points to spend."

local function get(t, k)
    if type(t) ~= "table" then return nil end
    return t[k]
end

function Tl.Unspent(client)
    local f = get(client, "unspentTalents")
    if type(f) ~= "function" then return nil end
    local ok, n = pcall(f)
    if not ok or type(n) ~= "number" or n ~= n or n < 0 or n == math.huge then return nil end
    return math.floor(n)
end

function Tl.Text(n)
    if n == 1 then return Tl.TEXT_ONE end
    return string.format(Tl.TEXT_MANY, n)
end

local function unlockedText(n)
    if n == 1 then return Tl.UNLOCKED_ONE end
    return string.format(Tl.UNLOCKED_MANY, n)
end

function Tl.Declare(k)
    k:Module({
        name = Tl.NAME,
        needs = { "client", "store", "bus", "settings", "advisor" },
        settings = {
            { key = Tl.SETTING, scope = "char", type = "bool", default = true,
              label = "Talent points",
              help = "Say when you have talent points to spend, and how many. It learns no talent.",
              group = "combat.spells", synonyms = { "talents", "talent points", "unspent", "spec" } },
        },
        start = function(ctx)
            local advisor = ctx.use("advisor")
            local shown = false

            local function remove()
                if shown then advisor.Remove(Tl.PROMPT) end
                shown = false
            end

            local function refresh()
                local ok, err = pcall(function()
                    if ctx.settings:get(Tl.SETTING) ~= true then remove(); return end
                    local level = ctx.client.level()
                    local points = Tl.Unspent(ctx.client)
                    if type(level) ~= "number" or level < Tl.LEVEL or points == nil then remove(); return end
                    if ctx.store:get("char", Tl.SAID) ~= true then
                        ctx.store:set("char", Tl.SAID, true)
                        if points > 0 then ctx.client.print(ns.id.title .. ": " .. unlockedText(points)) end
                    end
                    if points > 0 and ctx.client.inCombat() == false then
                        if advisor.Add(Tl.PROMPT, Tl.Text(points), Tl.PRIORITY) then shown = true end
                    else
                        remove()
                    end
                end)
                if not ok then k.problems:add("spells", "talent points", tostring(err)) end
            end

            -- The level-up to the talent level is said by Rotation/Spec.lua.
            local function onLevel(level)
                if type(level) == "number" and level == Tl.LEVEL then
                    ctx.store:set("char", Tl.SAID, true)
                end
                refresh()
            end

            ctx.bus:on(Tl.NAME, "PLAYER_LEVEL_UP", onLevel)
            ctx.bus:on(Tl.NAME, "CHARACTER_POINTS_CHANGED", refresh)
            ctx.bus:on(Tl.NAME, "PLAYER_REGEN_ENABLED", refresh)
            ctx.bus:on(Tl.NAME, "PLAYER_REGEN_DISABLED", refresh)
            refresh()
        end,
    })
end

-- The addon's own: declared when this file loads, started at login.
Tl.Declare(ns)
