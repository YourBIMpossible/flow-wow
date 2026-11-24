local _, ns = ...

-- The bag badge (G14, section 393): an item in the bags that is an upgrade
-- over what is worn carries a small badge on its bag slot naming the role
-- it is for: D (dps), T (tank), H (heal). The chosen role (spec.role) only
-- when the class pack has weights for it; none chosen, every role it is an
-- upgrade for. Look only: nothing here equips, moves or sells anything.
-- Legacy Flow's bag spec marks did the same on its own bag frame.
--
--   marks = GearBagBadge.Marks(client, packs, role)
--     { { bag, slot, text } ... } in bag then slot order; nil when the bags
--     cannot be read. An item not read yet, not gear, or one you cannot use
--     is never badged.
--   api   = GearBagBadge.Declare(k[, packs])   api.errors()
--
-- Reads: client.bagSlots, client.gear, class, level, weaponSkills (as the
-- tooltip verdict, Gear/Verdict.lua). Draws: client.markBagSlots(marks).
-- Redrawn on PLAYER_ENTERING_WORLD, BAG_UPDATE_DELAYED,
-- PLAYER_EQUIPMENT_CHANGED and PLAYER_LEVEL_UP.
-- Setting: gear.bagBadge (bool, account, on by default).
-- Not tested in game: the bag buttons the client finds (Core/Client.lua
-- markBagSlots) are a first guess on 16001.

local BB = {}
ns.GearBagBadge = BB

BB.NAME = "gearBagBadge"
BB.SETTING = "gear.bagBadge"
BB.ROLE = "spec.role"
BB.LETTER = { dps = "D", tank = "T", heal = "H" }

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function ask(client, read, ...)
    if type(client) ~= "table" or type(client[read]) ~= "function" then return nil end
    return client[read](...)
end

local function rolesFor(pack, role)
    local weights = type(pack) == "table" and type(pack.weights) == "table" and pack.weights or {}
    if type(role) == "string" and role ~= "" and type(weights[role]) == "table" then return { role } end
    local out = {}
    for r, w in pairs(weights) do
        if type(r) == "string" and type(w) == "table" then out[#out + 1] = r end
    end
    table.sort(out)
    return out
end

-- The letters of the roles this item is a usable upgrade for, or "".
local function letters(gear, pack, roles, level, skills)
    local text = ""
    for r = 1, #roles do
        local lines, detail = ns.GearVerdict.Lines(gear, { pack = pack, role = roles[r], level = level,
                                                            skills = skills })
        if lines == nil or type(detail) ~= "table" then return "" end
        if type(detail.use) ~= "table" or detail.use.can ~= true then return "" end
        local res = type(detail.result) == "table" and detail.result or {}
        if res.verdict == "upgrade" and finite(res.delta) and res.delta >= ns.GearTooltip.SAME then
            text = text .. (BB.LETTER[roles[r]] or roles[r]:sub(1, 1):upper())
        end
    end
    return text
end

function BB.Marks(client, packs, role)
    local rows = ask(client, "bagSlots")
    if type(rows) ~= "table" then return nil end
    local class = ask(client, "class")
    local pack
    if type(packs) == "table" and class ~= nil then pack = packs[class] end
    local roles = rolesFor(pack, role)
    local out = {}
    if #roles == 0 then return out end
    local level = ask(client, "level")
    local skills
    local okSkills, readSkills = pcall(ask, client, "weaponSkills")
    if okSkills and type(readSkills) == "table" then skills = readSkills end
    for _, row in ipairs(rows) do
        if type(row) == "table" and type(row.item) == "string" then
            local gear = ask(client, "gear", row.item)
            if type(gear) == "table" then
                local text = letters(gear, pack, roles, level, skills)
                if text ~= "" then out[#out + 1] = { bag = row.bag, slot = row.slot, text = text } end
            end
        end
    end
    return out
end

function BB.Declare(k, packs)
    local api = {}
    local ctx, errors, seen = nil, 0, {}
    function api.errors() return errors end

    local function problem(text)
        errors = errors + 1
        text = tostring(text)
        if not seen[text] then
            seen[text] = true
            k.problems:add("gear", "bag badge", text)
        end
    end

    local function draw(marks)
        local fn = ctx and ctx.client.markBagSlots
        if type(fn) ~= "function" then return end
        local ok, err = pcall(fn, marks)
        if not ok then problem(err) end
    end

    local function update()
        if not ctx then return end
        if ctx.settings:get(BB.SETTING) ~= true then return draw({}) end
        local ok, marks = pcall(BB.Marks, ctx.client, packs or ns.Packs, ctx.settings:get(BB.ROLE))
        if not ok then
            problem(marks)
            return draw({})
        end
        if marks == nil then return end -- not read: keep what is drawn
        draw(marks)
    end

    k:Module({
        name = BB.NAME,
        needs = { "client", "settings", "bus" },
        settings = { {
            key = BB.SETTING, scope = "account", type = "bool", default = true,
            label = "Badge upgrades in your bags",
            help = "An item in your bags that is an upgrade carries a letter for the role it is for"
                .. " (D dps, T tank, H heal). It equips nothing.",
            group = "gear", synonyms = { "bag", "badge", "spec", "upgrade", "role" },
        } },
        provides = { Errors = api.errors },
        start = function(c)
            ctx = c
            for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED",
                                     "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP" }) do
                c.bus:on(BB.NAME, event, update)
            end
            update()
        end,
        stop = function()
            draw({})
            ctx = nil
        end,
    })
    return api
end

ns.gearBagBadge = BB.Declare(ns)
