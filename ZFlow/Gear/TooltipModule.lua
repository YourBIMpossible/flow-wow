local _, ns = ...

-- The gear verdict on the game's item tooltip: hover a piece of gear and
-- read whether it is an upgrade for what you wear, for each role your class
-- pack has weights for. It only reads and adds lines of text; nothing is
-- equipped, moved or picked up.
--
--   lines = GearTooltipModule.Lines(client, packs, link)
--   api   = GearTooltipModule.Declare(k[, packs])
--     api.hooked()   true once the client's item tooltip is being followed
--     api.errors()   how many tooltips could not be worked out
--   ns.use(GearTooltipModule.NAME) -> { Hooked = api.hooked, Errors = api.errors }
--
-- Lines: the lines for one item link, { { text, tone } ... }, or nil when
-- nothing is to be said (not gear, or no gear read on this client).
--   One line per role, in name order, when you can use the item. A line
--   that would read the same for every role (can't use; no verdict) is
--   said once. Each of these is asked of the client and may be missing:
--     client.gear(link)   the item, what you wear, dual wield
--     client.class()      which class pack (packs[class])
--     client.level()      your level; no such read, or no answer: not known
--   Not known is never an upgrade (Gear/Verdict.lua).
--   Then, for a weapon whose speed was read, one speed line (G15,
--   Gear/WeaponSpeed.lua). An error working that line out leaves it off,
--   keeps the others, and is the second value: lines, err.
--
-- The module: one setting row, account wide, on by default:
--   gear.tooltip   "Gear verdict on item tooltips"
-- At start it asks the client to be told about item tooltips:
--   client.onItemTooltip(fn) -> cancel;  fn(link, add);  add(text, r, g, b)
-- A client without that hook (none of its two routes works), or one that
-- refuses it, leaves the module started and quiet: hooked() is false. With
-- the setting off nothing is worked out and nothing is added. An error
-- while working a tooltip out adds nothing to that tooltip, is counted, and
-- is kept as one "gear" problem per distinct error; the module goes on.

local M = {}
ns.GearTooltipModule = M

M.NAME = "gearTooltip"
M.SETTING = "gear.tooltip"

-- A line's colour by its tone: { r, g, b }. Authored here.
M.COLOUR = {
    good = { 0.1, 1, 0.1 },
    same = { 1, 1, 1 },
    bad = { 1, 0.3, 0.3 },
    none = { 0.6, 0.6, 0.6 },
}

-- One read of the client; nil when it has no such read.
local function ask(client, read, ...)
    if type(client) ~= "table" or type(client[read]) ~= "function" then return nil end
    return client[read](...)
end

-- The roles a pack has weights for, sorted.
local function rolesOf(pack)
    local out = {}
    if type(pack) == "table" and type(pack.weights) == "table" then
        for role, w in pairs(pack.weights) do
            if type(role) == "string" and type(w) == "table" then out[#out + 1] = role end
        end
    end
    table.sort(out)
    return out
end

function M.Lines(client, packs, link)
    local gear = ask(client, "gear", link)
    if type(gear) ~= "table" then return nil end
    local class = ask(client, "class")
    local pack = type(packs) == "table" and class ~= nil and packs[class] or nil
    local level = ask(client, "level")
    local roles = rolesOf(pack)

    local out, said = {}, {}
    local function keep(lines)
        for i = 1, #lines do
            if not said[lines[i].text] then
                said[lines[i].text] = true
                out[#out + 1] = lines[i]
            end
        end
    end
    -- With no role to score by, one pass still says why there is no verdict.
    for i = 1, math.max(#roles, 1) do
        local lines, detail = ns.GearVerdict.Lines(gear, { pack = pack, role = roles[i], level = level })
        if lines == nil then return nil end
        keep(lines)
        -- Whether you can use it does not depend on the role.
        if type(detail.use) ~= "table" or detail.use.can ~= true then break end
    end
    -- G15: a weapon's speed, last. No pack carries speed preferences yet, so
    -- no prefs are passed and the line names no role. An error here keeps
    -- the verdict lines and comes back as the second value.
    local ok, speed = pcall(function()
        local W = ns.GearWeaponSpeed
        return W.Line(W.From(gear))
    end)
    if not ok then return out, speed end
    if type(speed) == "table" then keep({ speed }) end
    return out
end

function M.Declare(k, packs)
    local api = {}
    local hooked, errors, cancel = false, 0, nil
    local seen = {}
    function api.hooked() return hooked end
    function api.errors() return errors end

    k:Module({
        name = M.NAME,
        needs = { "client", "store", "bus" },
        settings = { {
            key = M.SETTING, scope = "account", type = "bool", default = true,
            label = "Gear verdict on item tooltips",
            help = "Hover a piece of gear to read whether it is an upgrade for what you wear. It changes nothing.",
            group = "gear", synonyms = { "upgrade", "tooltip", "compare", "armor", "weapon" },
        } },
        provides = { Hooked = api.hooked, Errors = api.errors },
        start = function(ctx)
            if type(ctx.client.onItemTooltip) ~= "function" then return end
            local got = ctx.client.onItemTooltip(function(link, add)
                if ctx.settings:get(M.SETTING) ~= true or type(add) ~= "function" then return end
                -- Every line is worked out before the first is added, so an
                -- error leaves the tooltip as the game made it.
                local ok, lines, partErr = pcall(M.Lines, ctx.client, packs or ns.Packs, link)
                local err = partErr
                if not ok then err = lines end
                if err ~= nil then
                    errors = errors + 1
                    local text = tostring(err)
                    if not seen[text] then
                        seen[text] = true
                        k.problems:add("gear", "tooltip", text)
                    end
                end
                if not ok then return end
                for i = 1, #(lines or {}) do
                    local colour = M.COLOUR[lines[i].tone] or M.COLOUR.none
                    add(lines[i].text, colour[1], colour[2], colour[3])
                end
            end)
            if type(got) == "function" then
                cancel, hooked = got, true
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
ns.gearTooltip = M.Declare(ns)
