local _, ns = ...
-- S15 click slots (P-KEYS slice C): the pure part of Rotation/ClickSlots.lua.
-- The slot plan from the rotation key's attribute rows and the care key's
-- plan, the rows each slot is given, and the button the key frame sets
-- them through. Hand-made rows; not tested in game.
local tests = {}

local S = ns.ClickSlots
local K = ns.KeyFrame

-- Attribute rows as Rotation/Cast.lua C.Attributes gives them.
local function rows(map)
    local out = {}
    for attr, value in pairs(map) do out[#out + 1] = { attr = attr, value = value } end
    return out
end

local function byAttr(list)
    local out = {}
    for _, r in ipairs(list) do out[r.attr] = r.value end
    return out
end

-- A row handle as the client's clickRow gives it, in memory.
local function fakeRow(locked)
    local row = { slots = {}, holder = false, locked = locked }
    for i = 1, #S.SLOTS do row.slots[i] = { attrs = {}, shown = false } end
    function row.set(i, attr, value)
        if row.locked then return false, "lockdown" end
        local slot = row.slots[i]
        if not slot then return false, "absent" end
        slot.attrs[attr] = value
        return true
    end
    function row.get(i, attr)
        local slot = row.slots[i]
        if not slot then return nil end
        return slot.attrs[attr]
    end
    function row.show(i, on)
        if row.locked then return false, "lockdown" end
        if i == 0 then row.holder = on == true return true end
        local slot = row.slots[i]
        if not slot then return false, "absent" end
        slot.shown = on == true
        return true
    end
    function row.isShown(i)
        if i == 0 then return row.holder end
        local slot = row.slots[i]
        return slot ~= nil and slot.shown
    end
    return row
end

tests["click slots: the slots in order, key first and care second"] = function(t)
    t.eq(S.SLOTS, { "key", "care", "ctrl", "shift", "alt", "more" })
    t.eq(S.SETTING, "rotation.clickSlots")
    t.eq(S.Width(), #S.SLOTS * S.SIZE + (#S.SLOTS - 1) * S.GAP)
end

tests["click slots plan: the key, the care key and the plan's modifiers"] = function(t)
    local plan = S.Plan(rows({
        type = "spell", spell = "Smite", unit = "target",
        ["*type-ctrl"] = "spell", ["*spell-ctrl"] = "Renew", ["*unit-ctrl"] = "player",
        ["*type-shift"] = "spell", ["*spell-shift"] = "Mind Blast", ["*unit-shift"] = "target",
        ["*type-alt"] = "item", ["*item-alt"] = "item:5512",
    }), { key = { spell = "Flash Heal", unit = "party1" } })
    t.eq(plan.key, { spell = "Smite", unit = "target" })
    t.eq(plan.care, { spell = "Flash Heal", unit = "party1" })
    t.eq(plan.ctrl, { spell = "Renew", unit = "player" })
    t.eq(plan.shift, { spell = "Mind Blast", unit = "target" })
    t.eq(plan.alt, { item = "item:5512" }, "the healing item on its own slot")
    t.eq(plan.more, nil, "nothing on Ctrl+Shift: an empty slot")
end

tests["click slots plan: an item on the key, and nothing known gives empty slots"] = function(t)
    local plan = S.Plan(rows({ type = "item", item = "item:2287" }), nil)
    t.eq(plan.key, { item = "item:2287" })
    t.eq(plan.care, nil, "no care plan: the care slot is empty")
    t.eq(S.Plan(nil, nil), {}, "no rows, no care: every slot empty")
    t.eq(S.Plan(rows({ type = "spell" }), { key = { unit = "player" } }), {}, "a type with no spell is no slot")
end

tests["click slots rows: each slot's parts, then the row shown last"] = function(t)
    local list = S.Rows({ key = { spell = "Smite", unit = "target" }, alt = { item = "item:5512" } })
    local m = byAttr(list)
    t.eq({ m["1:type"], m["1:spell"], m["1:unit"], m["1:item"], m["1:shown"] }, { "spell", "Smite", "target", nil, true })
    t.eq({ m["5:type"], m["5:spell"], m["5:item"], m["5:shown"] }, { "item", nil, "item:5512", true })
    t.eq({ m["2:type"], m["2:shown"] }, { nil, nil }, "the empty care slot is cleared and hidden")
    t.eq(list[#list].attr, "0:shown", "the row itself is shown last")
    t.eq(list[#list].value, true)
    t.eq(#list, #S.SLOTS * 5 + 1)
end

tests["click slots rows: never a macro type or macro text (section 246)"] = function(t)
    local list = S.Rows(S.Plan(rows({ type = "spell", spell = "Attack",
        ["*type-alt"] = "item", ["*item-alt"] = "item:5512" }), { key = { spell = "Renew", unit = "player" } }))
    for _, r in ipairs(list) do
        t.ok(not tostring(r.attr):lower():find("macro", 1, true), "no macro attribute: " .. tostring(r.attr))
        t.ok(tostring(r.value):lower() ~= "macro", "no macro value on " .. tostring(r.attr))
    end
end

tests["click slots signature: the same plan, the same signature; a change, another"] = function(t)
    local a = { key = { spell = "Smite", unit = "target" } }
    t.eq(S.Signature(a), S.Signature({ key = { spell = "Smite", unit = "target" } }))
    t.ok(S.Signature(a) ~= S.Signature({ key = { spell = "Mind Blast", unit = "target" } }))
    t.eq(S.Signature(nil), "clear")
end

tests["click slots button: a slot's part goes to that slot; shown shows it"] = function(t)
    local row = fakeRow(false)
    local b = S.Button(row)
    t.eq(b.set("2:spell", "Renew"), true)
    t.eq(row.slots[2].attrs.spell, "Renew")
    t.eq(b.get("2:spell"), "Renew")
    t.eq(b.set("3:shown", true), true)
    t.eq(row.slots[3].shown, true)
    t.eq(b.get("3:shown"), true)
    t.eq(b.set("3:shown", nil), true)
    t.eq(b.get("3:shown"), nil, "hidden reads back as nothing held")
    t.eq(b.set("0:shown", true), true)
    t.eq(row.holder, true, "slot 0 is the row itself")
    local ok, why = b.set("nonsense", 1)
    t.eq({ ok, why }, { false, "refused" })
end

tests["click slots through the key frame: set out of a fight, frozen in one"] = function(t)
    local row = fakeRow(false)
    local lock = false
    local kf = K.New({ button = S.Button(row), lockdown = function() return lock end,
        rows = S.Rows, signature = S.Signature })
    local st = kf:want({ key = { spell = "Smite", unit = "target" } })
    t.eq(st.state, "set")
    t.eq(row.slots[1].attrs.spell, "Smite")
    t.eq(row.holder, true)
    lock = true; row.locked = true
    st = kf:want({ key = { spell = "Mind Blast", unit = "target" } })
    t.eq(st.state, "waiting")
    t.eq(st.reason, "lockdown")
    t.eq(row.slots[1].attrs.spell, "Smite", "frozen in the fight")
    lock = nil
    st = kf:try(true)
    t.eq(st.reason, "lockdownUnknown", "a lock that is not a plain false is the lock")
    lock = false; row.locked = false
    st = kf:try(true)
    t.eq(st.state, "set")
    t.eq(row.slots[1].attrs.spell, "Mind Blast", "set after the fight")
    st = kf:want(nil)
    t.eq(st.state, "cleared")
    t.eq({ row.holder, row.slots[1].shown, row.slots[1].attrs.spell }, { false, false, nil })
end

tests["click slots lines: off, waiting, set and failed say so"] = function(t)
    t.ok(S.Lines(nil)[1]:find("off", 1, true) ~= nil)
    t.ok(S.Lines({ state = "waiting", reason = "lockdown" })[1]:find("fight", 1, true) ~= nil)
    local set = table.concat(S.Lines({ state = "set", held = { ["1:spell"] = "Smite", ["2:spell"] = "Renew" } }), " ")
    t.ok(set:find("key: Smite", 1, true) ~= nil, set)
    t.ok(set:find("care: Renew", 1, true) ~= nil, set)
    t.ok(set:find("click", 1, true) ~= nil, "says the slots act on your click: " .. set)
    t.ok(S.Lines({ state = "failed", failed = { { attr = "1:spell", why = "refused" } }, parts = 3 })[1]
        :find("could not be set", 1, true) ~= nil)
end

return tests
