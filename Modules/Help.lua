-- /flow help (also plain /flow). Topics are registered, so new features add
-- their own help without touching this file:
--   ns:Register("help", key, { order = n, title = "...", lines = { "...", ... } })

local _, ns = ...

local topics = {
    { "basics", 10, "Basics", {
        "Hold |cffffd200Shift|r and drag any Flow element to move it.",
        "/flow splash - replay the intro on the arrow (on/off)",
        "/flow api - what this game client lets addons see",
    } },
    { "rotation", 20, "Rotation (icon + glowing action button)", {
        "Green = attack, light blue = buff, gold = heal, fast gold pulse = heal now.",
        "Click the icon or press your Flow key to cast it (set the key in /flow settings).",
        "In combat the key keeps the spell it had at the pull; a small \"key:\" icon shows it.",
        "/flow rot guide - your rotation in plain words; /flow rot why - why each spell is or isn't suggested",
        "/flow rot on|off|unlock|lock|stats|known|reset",
    } },
    { "advice", 30, "Advice (round spyglass button with a count)", {
        "Hover for a quick list; click to open it. Rows with an arrow route you there. /flow advice prints it.",
    } },
    { "nav", 40, "Arrow", {
        "Plans your whole trip: objectives, turn-ins (after their objectives), quests to accept,",
        "trainers, and fishing/gathering when it is on the way. Click for the full plan.",
        "Left-click: details. Right-click: next goal. Learns trails as you walk.",
        "Right-click a stop on the map or in the route list to hide it. To undo: tick \"Show hidden stops\" under the map list and click one, or /flow nav unhide (all of them; /flow nav hidden lists them).",
        "World map: numbered checkpoints with levels \"3 [9]\", quest pickups \"!2\". Hover to preview",
        "  (yellow), click to choose. Advice list rows with an arrow do the same. /flow map on|off",
        "Waypoint: Ctrl- or Alt-click the world map, or /flow way <x> <y> [note]; /flow way clear",
        "/flow nav quests|optimal - follow only current quests, or the optimal path (also on the map panel)",
        "/flow nav professions on|off - trainer and skill-up stops; /flow nav why - what the route is made of",
        "/flow prof plan - how Flow plans to raise your professions (what to make, materials, where from)",
        "/flow test [name] - run Flow's self-tests (also run on every /reload into the diagnostics)",
        "/flow copy - what Flow said in chat lately, in a box you can copy from (web addresses too)",
        "/flow nav xp on|off - most XP first (default) or shortest path; hover a quest stop for its XP",
        "/flow nav stops 1|3|5|10|all - how many of your next stops the map and Flow Tracker show (also in the arrow menu)",
        "Map: the square button above the game's quest log button opens and closes Flow's route list (one or the other, or neither)",
        "/flow nav on|off|learn|forget",
    } },
    { "quests", 50, "Quests", {
        "Nameplate marks: skull = kill (count), diamond = drops what you need, star = talk.",
        "/flow quest (plates turns nameplates on), /flow missed - quests you skipped",
    } },
    { "gear", 60, "Gear", {
        "Tooltips: score per role and +/- vs what each item would replace (or your role's set).",
        "/flow gear sets | set <role> <set name> | save <role> | offspec | on|off",
        "/flow spec - levelling spec advice; /flow spec dps|heal|tank|auto",
        "Bags: green arrow = equip now, spec icons = better for another role, gold coin = sell, AH, DE,",
        "  quest ! = needed for a quest, profession icon = crafting material. Tooltips say why. /flow bags on|off",
        "Vendors: Flow lists what to sell; sells 12 at a time on click, buy back any (it learns). /flow sell",
    } },
    { "learning", 70, "Learning from your fights", {
        "/flow fights - best vs worst fights per fight type",
        "/flow log auto - write the combat log file every session, for Claude's reports",
    } },
}
for _, t in ipairs(topics) do
    ns:Register("help", t[1], { order = t[2], title = t[3], lines = t[4] })
end

local function version()
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    return get and get(ns.name, "Version") or "?"
end
ns.Version = version

ns.commands.help = function()
    local list = {}
    for _, t in ns:Each("help") do list[#list + 1] = t end
    table.sort(list, function(a, b) return (a.order or 100) < (b.order or 100) end)
    ns:Print("v" .. version() .. " help")
    for _, t in ipairs(list) do
        print("|cffffd200" .. t.title .. "|r")
        for _, l in ipairs(t.lines) do print("   " .. l) end
    end
end
