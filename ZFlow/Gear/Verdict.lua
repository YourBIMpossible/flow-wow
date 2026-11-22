local _, ns = ...

-- The gear verdict for one item: from what the client answered about it to
-- the lines for its tooltip, in one step. Pure: it joins Gear/Read.lua,
-- Gear/Score.lua, Gear/CanUse.lua and Gear/Tooltip.lua and reads nothing
-- itself. Nothing unknown becomes a number, and nothing unknown becomes an
-- upgrade.
--
--   lines, detail = GearVerdict.Lines(gear, who)
--
--   gear   what client.gear(link) answers: { kind, stats, worn, dualWield }.
--          The item's classID, subclassID and minLevel are read from the
--          same table (client.gear gives them once the item is loaded);
--          without them the answer is "No verdict", never a yes.
--          `unmet`, when it is there, is the list of requirements the game
--          itself marks as not met on the item (Gear/Usable.lua). It goes
--          ahead of the class pack's table: the game's yes or no stands.
--   who    { pack, role, level }
--     pack   the class pack (ns.Packs[class]): its `weights[role].values`
--            and its `proficiency` are used as they are, with the evidence
--            labels they carry. No weight and no proficiency is made here.
--     role   which of the pack's weights to score by ("dps", "tank", ...)
--     level  your level
--   lines  GearTooltip.Lines' answer, or nil when nothing is to be said:
--          the item is not known to be gear (no equip location), or is of a
--          kind that is not compared (a bag, a shirt). nil is not a verdict.
--   detail { why } with no lines; else { result, use, unmapped, ignored,
--          weights }: the scorer's answer, the can-use answer, Gear/Read's
--          two lists, and the evidence label of the weights used (nil when
--          there were none), for a diagnostic line and for tests.

local V = {}
ns.GearVerdict = V

V.REASON = {
    notGear = "not known to be gear that is compared",
}

function V.Lines(gear, who)
    if type(gear) ~= "table" or type(gear.kind) ~= "string" or gear.kind == "" then
        return nil, { why = V.REASON.notGear }
    end
    who = type(who) == "table" and who or {}
    local pack = type(who.pack) == "table" and who.pack or {}

    local weights, evidence = nil, nil
    local forRole = type(pack.weights) == "table" and pack.weights[who.role] or nil
    if type(forRole) == "table" then
        weights = forRole.values
        if type(forRole.evidence) == "string" then evidence = forRole.evidence end
    end

    local shapes = ns.GearRead.Shapes(gear)
    local result = ns.GearScore.Compare(shapes.candidate, shapes.equipped, weights, shapes.can)
    if result.reason == ns.GearScore.REASON.kind then
        return nil, { why = V.REASON.notGear }
    end
    -- Whether you can use it: what the game itself marks on the item
    -- (gear.unmet, Gear/Usable.lua) when that was read; else the class
    -- pack's table, a first guess that says so on the line.
    local packUse = ns.GearCanUse.Check(
        { classID = gear.classID, subclassID = gear.subclassID, minLevel = gear.minLevel },
        { proficiency = pack.proficiency, level = who.level })
    local use = ns.GearUsable.Best(ns.GearUsable.Check(gear.unmet), packUse)
    local lines = ns.GearTooltip.Lines(result, use, { role = who.role })
    return lines, { result = result, use = use, unmapped = shapes.unmapped, ignored = shapes.ignored,
                    weights = evidence }
end
