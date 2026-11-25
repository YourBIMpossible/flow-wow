local _, ns = ...
-- Package P-SETS, G13 (lead DISPATCH section 229 item 7): the keep-off-spec
-- rule. Gear in the bags that is an upgrade for another role of your class
-- is kept "better for <role>" at the merchant, while the setting
-- gear.keepOffspec (default on) holds; off, it is not kept for that. The
-- whole add-on on a fake client with the real class packs; the merchant's
-- sell list is the entry point. Per section 236: item data late, a read
-- that raises then recovers, a reload. Class parity: every class pack.
-- Look only. Made-up items. Not tested in game.
local tests = {}

local STR, DODGE = "ITEM_MOD_STRENGTH_SHORT", "ITEM_MOD_DODGE_RATING_SHORT"
local WORN = "item:4000:0:0:0:0:0:0:0"
local GUARD = "item:4001:0:0:0:0:0:0:0"      -- dodge: a tank upgrade, worse for dps
local CLOAK = "item:4002:0:0:0:0:0:0:0"      -- grey: junk either way
local INFO = {
    [4001] = { name = "Guard Helm", quality = 2, sellPrice = 50, classID = 4 },
    [4002] = { name = "Frayed Cloak", quality = 0, sellPrice = 4, classID = 4 },
}

local function helm(stats)
    return { kind = "INVTYPE_HEAD", stats = stats, classID = 4, subclassID = 3, minLevel = 1, unmet = {} }
end

-- opts: role (spec.role for the character), keep (account
-- settings.gear.keepOffspec), late (the guard helm's gear data not given),
-- account/char (saved tables to boot from: a reload).
local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    local account = opts.account
    if account == nil then
        account = {}
        if opts.keep ~= nil then account.settings = { gear = { keepOffspec = opts.keep } } end
    end
    local char = opts.char
    if char == nil then
        char = {}
        if opts.role then char.settings = { spec = { role = opts.role } } end
    end
    c.setSaved(ns.id.accountDB, account)
    c.setSaved(ns.id.charDB, char)
    c.setClass("WARRIOR")
    c.setLevel(10)
    c.setDualWield(false)
    c.setItemInfo(INFO)
    c.setItem(WORN, helm({ [STR] = 4 }))
    if not opts.late then c.setItem(GUARD, helm({ [DODGE] = 10 })) end
    c.setWorn(1, WORN)
    c.setBagItems({ { item = GUARD, count = 1 }, { item = CLOAK, count = 1 } })
    local addon = ns.offline.addon(c)
    c.lists = { SellList = addon.sellList }
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function joinedLines(lines) return table.concat(lines or {}, " / ") end

local function hasLine(lines, text)
    for _, l in ipairs(lines or {}) do
        if l == text then return true end
    end
    return false
end

local function startsWith(lines, prefix)
    for _, l in ipairs(lines or {}) do
        if l:sub(1, #prefix) == prefix then return true end
    end
    return false
end

-- One merchant visit: the sell list's text lines while the window is open,
-- as drawn (item names in their quality colour, Items/Present.lua Tint).
local function rawVisit(c)
    c.setMerchantOpen(true)
    local out = {}
    for i, l in ipairs(c.lists.SellList.last() or {}) do out[i] = l end
    c.setMerchantOpen(false)
    return out
end

-- The same with the colour codes taken off, to compare the words.
local function merchantVisit(c)
    local out = rawVisit(c)
    for i, l in ipairs(out) do out[i] = ns.ItemPresent.Plain(l) end
    return out
end

local KEPT = "Guard Helm: better for Protection"

-- Fails before: UI/SellList.lua gives Disposition no gear facts, role or
-- kept roles (Gear/OffSpec.lua is absent), so laterOrOtherRole says
-- nothing and hasLine(KEPT) is false.
tests["off-spec: a tank upgrade is kept for a dps warrior, naming the role"] = function(t)
    local c = boot({ role = "dps" })
    local lines = merchantVisit(c)
    t.ok(hasLine(lines, KEPT), "kept for the other role: " .. joinedLines(lines))
    t.ok(startsWith(lines, "1 x Frayed Cloak: "), "grey junk is still offered: " .. joinedLines(lines))
    -- The kept name is in the colour of its quality (uncommon), tinted once.
    local raw = joinedLines(rawVisit(c))
    t.ok(raw:find(ns.ItemPresent.Tint("Guard Helm", 2) .. ": better for Protection", 1, true) ~= nil,
        "the kept name carries its quality colour: " .. raw)
end

-- Fails before: no role is given to Disposition, so the chosen role's
-- upgrade is not said (hasLine false).
tests["off-spec: for the chosen role it is an upgrade you can wear now"] = function(t)
    local c = boot({ role = "tank" })
    local lines = merchantVisit(c)
    t.ok(hasLine(lines, "Guard Helm: an upgrade you can wear now"), joinedLines(lines))
end

-- Fails before: as the first test (no keep line with the setting on either).
tests["off-spec: no role chosen keeps it for any role it suits; the setting off does not"] = function(t)
    local c = boot()
    t.ok(hasLine(merchantVisit(c), KEPT), "no role chosen: kept for Protection")
    local off = boot({ role = "dps", keep = false })
    local lines = merchantVisit(off)
    t.ok(not hasLine(lines, KEPT), "setting off: not kept for another role: " .. joinedLines(lines))
    t.ok(not startsWith(lines, "1 x Guard Helm: "), "and never offered for sale: " .. joinedLines(lines))
end

-- Section 236: late data. Fails before at the second visit (no keep line).
tests["off-spec: item data late - kept once it is read"] = function(t)
    local c = boot({ role = "dps", late = true })
    t.ok(not hasLine(merchantVisit(c), KEPT), "not kept while its stats are not known")
    c.setItem(GUARD, helm({ [DODGE] = 10 }))
    t.ok(hasLine(merchantVisit(c), KEPT), "kept once read")
end

-- Section 236: a read that raises, then recovers. Fails before at the
-- recovered visit (no keep line).
tests["off-spec: the gear read raising lists the rest; once it recovers it keeps"] = function(t)
    local c = boot({ role = "dps" })
    local real = c.gear
    c.gear = function() error("Wolves") end
    local lines = merchantVisit(c)
    t.ok(startsWith(lines, "1 x Frayed Cloak: "), "the list is still made: " .. joinedLines(lines))
    t.ok(not hasLine(lines, KEPT), "no keep line from a failed read")
    c.gear = real
    t.ok(hasLine(merchantVisit(c), KEPT), "kept once the read recovers")
end

-- Section 236: a reload keeps the setting and the answer. Fails before
-- (no keep line on either boot).
tests["off-spec: after a reload the same saved data gives the same answer"] = function(t)
    local c = boot({ role = "dps" })
    t.ok(hasLine(merchantVisit(c), KEPT), "first boot")
    local again = boot({ account = c.saved(ns.id.accountDB), char = c.saved(ns.id.charDB) })
    t.ok(hasLine(merchantVisit(again), KEPT), "after the reload")
    local off = boot({ role = "dps", keep = false })
    local offAgain = boot({ account = off.saved(ns.id.accountDB), char = off.saved(ns.id.charDB) })
    t.ok(not hasLine(merchantVisit(offAgain), KEPT), "the setting off survives the reload")
end

-- Class parity: every class pack. Fails before: ns.GearOffSpec is nil.
tests["off-spec: every class pack gives its roles and their names"] = function(t)
    local O = ns.GearOffSpec
    t.ok(type(O) == "table", "Gear/OffSpec.lua is loaded")
    if type(O) ~= "table" then return end
    local seen = 0
    for class, pack in pairs(ns.Packs) do
        if type(pack) == "table" and type(pack.weights) == "table" then
            seen = seen + 1
            local client = { class = function() return class end, level = function() return 10 end }
            local facts = O.Facts(client, nil, ns.Packs, {})
            t.ok(type(facts) == "table", class .. ": facts")
            local want, got = {}, {}
            for role in pairs(pack.weights) do want[#want + 1] = role end
            for role, on in pairs(type(facts) == "table" and facts.keptRoles or {}) do
                if on == true then got[#got + 1] = role end
            end
            table.sort(want); table.sort(got)
            t.eq(got, want, class .. ": every weighted role is kept by default")
            for _, role in ipairs(want) do
                local names = type(facts) == "table" and facts.roleNames or {}
                t.ok(type(names[role]) == "string" and names[role] ~= "", class .. " " .. role .. " has a name")
            end
        end
    end
    t.eq(seen, 9, "nine class packs")
end

-- Parity row C-32, the data half (lead section 789): a tick per role, as
-- Flow's keep-set ticks under the bags (Modules/Gear/KeepSets.lua
-- :277-285), saved per character at O.KEEP_FOR_PATH ({ [role] = true |
-- false }). With no ticks saved, the one switch gear.keepOffspec works
-- exactly as before (every role, or none). The ticks are the drawing
-- lane's. Fails before: one switch only.
tests["off-spec C-32: which roles to keep gear for, from ticks, else the one switch"] = function(t)
    local O = ns.GearOffSpec
    t.eq(type(O.KeepFor), "function")
    if type(O.KeepFor) ~= "function" then return end
    local roles = { "dps", "heal", "tank" }
    t.eq(O.KeepFor(nil, roles, nil), { dps = true, heal = true, tank = true }, "no ticks, switch on as made: all")
    t.eq(O.KeepFor(nil, roles, true), { dps = true, heal = true, tank = true })
    t.eq(O.KeepFor(nil, roles, false), nil, "no ticks, switch off: none, as before")
    t.eq(O.KeepFor({}, roles, false), nil, "an empty tick list is no ticks")
    t.eq(O.KeepFor({ tank = true, heal = false }, roles, false), { tank = true }, "ticks win over the switch")
    t.eq(O.KeepFor({ heal = false, tank = false }, roles, true), nil, "every tick off: none")
    t.eq(O.KeepFor({ wizard = true }, roles, true), { dps = true, heal = true, tank = true },
        "a tick for no role of yours counts for nothing: the switch")
end

tests["off-spec C-32: the facts read your ticks; with none saved they are as before"] = function(t)
    local O = ns.GearOffSpec
    if type(O.KeepFor) ~= "function" then return t.ok(false, "no KeepFor") end
    local client = { class = function() return "WARRIOR" end, level = function() return 10 end }
    local function store(account, char)
        return { get = function(_, scope, path)
            if scope == "account" and path == O.PATH then return account end
            if scope == "char" and path == O.KEEP_FOR_PATH then return char end
            return nil
        end }
    end
    local all = O.Facts(client, store(nil, nil), ns.Packs, {})
    local before = O.Facts(client, nil, ns.Packs, {})
    t.eq(all.keptRoles, before.keptRoles, "no ticks: the same as before")
    local off = O.Facts(client, store(false, nil), ns.Packs, {})
    t.eq(off.keptRoles, nil, "switch off, no ticks: none")
    local role = next(ns.Packs.WARRIOR.weights)
    local one = O.Facts(client, store(false, { [role] = true }), ns.Packs, {})
    t.eq(one.keptRoles, { [role] = true }, "your one tick")
end

return tests
