-- The help window (G54, WHITE-QUEUE C3): a guide a new player can read,
-- one page for each feature. Left: the features. Right: the picked one in
-- plain words, what it shows, then the commands that belong to it, each
-- with what it does. The search in the header narrows the features.
--
-- The pages are written here (H.PAGES). A command is shown only while the
-- slash command has that word (diag.commands), so a page never names a
-- command this add-on does not have; its hover text is the command's own
-- help line (diag.help), the same words `<slash> help` prints.
--
-- Built from the kit's parts only (UI/Kit.lua, drawn by client.kitWindow):
-- this file names no template, colour, font or size.
--
-- LOOK ONLY: it runs no command and changes no setting. Nothing is cast,
-- sold, bought, moved or sent.
--
--   H.Page(page, commands, help, slash) -> lines   (pure) a page's parts
--   H.Search(pages, text) -> pages                 (pure) the pages with it
--   H.Declare(k, diag) -> api     api.Open(), api.Close(), api.Shown()
--   `<slash> guide` opens it.
-- Its place is kept, account wide, at H.PATH.
-- Not tested in game.
local _, ns = ...

local H = {}
ns.HelpPages = H

H.NAME = "helpPages"
H.ID = "guide"
H.WORD = "guide"
H.HELP = "open the guide: one page for each feature, in plain words"
H.HEADER = "Guide"
H.SEARCH = "Search the guide"
H.COMMANDS = "What to type"
H.NO_MATCH = { "No page has that word.", "Clear the search to see every page." }
H.NO_COMMANDS = { "This page has no command in this version.", "Pick another page on the left." }
H.FOOTER = "%s help lists every command in chat."
H.WIDTH, H.HEIGHT = 640, 460
-- Where the window was left, account wide: { point, width, height }.
H.PATH = "layout.helpPages"

-- The pages. about: { text, sub } lines, short enough to stand on one line.
-- words: { word (the slash word it needs), say (what to type after the
-- slash, the word itself when left out), text (what it does) }.
H.PAGES = {
    { id = "start", title = "Start here",
      about = {
          { "This add-on shows and advises. You press the keys.",
            "It never casts, sells, buys or moves for you." },
          { "Pick a feature on the left to read about it.",
            "Each page says what you see and what to type." },
          { "Hold the mouse over a command for more about it." },
      },
      words = {
          { word = "settings", text = "Open the settings" },
          { word = "intro", text = "Show the introduction again" },
          { word = "guide", text = "Open this guide" },
          { word = "help", text = "List every command in chat" },
      } },
    { id = "quests", title = "Quests and the arrow",
      about = {
          { "The arrow points at your next quest step.",
            "Walk where it points. It never moves you." },
          { "A route puts this map's quests in a walking order.",
            "Plan one, then follow the arrow from stop to stop." },
      },
      words = {
          { word = "route", text = "Plan a route from the quests in your log" },
          { word = "route", say = "route skip", text = "Leave out the stop you are on" },
          { word = "route", say = "route new", text = "Plan the route again" },
          { word = "route", say = "route off", text = "Clear the route" },
          { word = "tracker", text = "Open the route window" },
          { word = "walk", text = "Walk to this step instead of the shortcut" },
          { word = "questitems", text = "The quest items named on the arrow" },
      } },
    { id = "stops", title = "Vendors, inns and other stops",
      about = {
          { "The arrow can point at places you have seen.",
            "A vendor, a repairer, a bank, an inn, a flight master or an auction house." },
          { "A trip is your own list of stops, walked in order." },
      },
      words = {
          { word = "stop", text = "Point the arrow at the nearest stop you have seen" },
          { word = "trip", text = "Make a list of stops to visit" },
          { word = "follow", text = "Point the arrow at a party member" },
          { word = "share", text = "Offer one quest from your log to your group" },
          { word = "trails", text = "The paths you walked into caves" },
      } },
    { id = "dungeons", title = "Dungeons",
      about = {
          { "One window lists each dungeon and its quests.",
            "It says which to pick up before you go in." },
      },
      words = {
          { word = "dungeons", text = "Open the Dungeon Quests window; with a dungeon's name, plan that run" },
          { word = "dungeon", text = "Say the dungeon you are in: your quests for it and the bosses killed" },
      } },
    { id = "gear", title = "Gear",
      about = {
          { "Each piece of gear gets a verdict for your role.",
            "You decide what to wear. Nothing is equipped for you." },
      },
      words = {
          { word = "role", text = "Show your role, or set it: dps, heal or tank" },
          { word = "gear", say = "gear why", text = "Each piece in your bags, with its verdict" },
          { word = "set", say = "set save <name>", text = "Save what you wear as a named set" },
          { word = "roll", say = "roll <item link>", text = "Need or Greed advice. It never rolls." },
          { word = "enchant", text = "Show the enchant on your weapons" },
      } },
    { id = "bags", title = "Bags, bank and auctions",
      about = {
          { "Advice on what to bank and what is worth auctioning.",
            "Prices come from your own auction searches only." },
          { "Nothing is moved, posted or bought for you." },
      },
      words = {
          { word = "banker", text = "What to put in the bank now" },
          { word = "buyback", text = "At a merchant: what you can buy back" },
          { word = "auctions", text = "What in your bags is worth the auction house" },
          { word = "auction", text = "The prices seen in your own searches" },
          { word = "trader", text = "Deals among your own searches this session" },
      } },
    { id = "professions", title = "Professions",
      about = {
          { "Advice on which professions to learn and what to make next." },
          { "The add-on remembers the nodes you gathered." },
      },
      words = {
          { word = "professions", text = "Which profession to learn" },
          { word = "nodes", text = "The nearest nodes you gathered" },
          { word = "nodes", say = "nodes go", text = "Point the arrow at the nearest one" },
      } },
    { id = "fights", title = "Fights",
      about = {
          { "See what happened in your last fights.",
            "Marks on enemy nameplates show threat and quest targets." },
      },
      words = {
          { word = "fights", text = "Your last fights: dealt, taken and healed" },
          { word = "threat", text = "Your threat on enemy nameplates: on or off" },
          { word = "questmarks", text = "Quest marks on enemy nameplates: on or off" },
          { word = "combo", text = "Combo points on your target's nameplate: on or off" },
          { word = "keys", text = "Show what your rotation button holds" },
      } },
    { id = "chat", title = "Chat and sound",
      about = {
          { "Chat links, a copy button and easier reading.",
            "NPCs can read their words aloud." },
      },
      words = {
          { word = "chat", text = "How each chat helper is set" },
          { word = "speech", text = "NPCs reading aloud: on, off, or a test line" },
          { word = "audioreset", text = "Restart the game's sound when it goes silent" },
      } },
    { id = "wrong", title = "If something is wrong",
      about = {
          { "The add-on can say what is not working.",
            "You can also write a report to copy and send." },
      },
      words = {
          { word = "diag", text = "Say what is not working" },
          { word = "feedback", text = "Write a problem or an idea, and copy the report" },
          { word = "buttons", text = "Why a window button is not shown" },
      } },
}

local function isText(v) return type(v) == "string" and v ~= "" end

-- The pages whose title, lines or commands have the text; every page for
-- no text. Plain text, never a pattern; letter case does not matter.
function H.Search(pages, text)
    local out = {}
    local want = isText(text) and text:lower() or nil
    for _, p in ipairs(type(pages) == "table" and pages or {}) do
        local found = want == nil
        local function has(s)
            if not found and isText(s) and s:lower():find(want, 1, true) then found = true end
        end
        has(p.title)
        for _, a in ipairs(p.about or {}) do has(a[1]); has(a[2]) end
        for _, w in ipairs(p.words or {}) do has(w.word); has(w.say); has(w.text) end
        if found then out[#out + 1] = p end
    end
    return out
end

-- A page's parts for the pane: its heading, what it shows, then a line for
-- each command the slash command has.
function H.Page(page, commands, help, slash)
    local out = { { kind = "section", key = "page", text = page.title, big = true } }
    for i, a in ipairs(page.about or {}) do
        out[#out + 1] = { kind = "line", key = "about." .. i, text = a[1], sub = a[2] }
    end
    out[#out + 1] = { kind = "section", key = "commands", text = H.COMMANDS }
    local n = 0
    for _, w in ipairs(page.words or {}) do
        if type(commands) == "table" and type(commands[w.word]) == "function" then
            n = n + 1
            local said = type(help) == "table" and help[w.word] or nil
            out[#out + 1] = { kind = "line", key = "word." .. n, text = tostring(slash) .. " " .. (w.say or w.word),
                sub = w.text, tooltip = isText(said) and said or nil }
        end
    end
    if n == 0 then
        out[#out + 1] = { kind = "empty", key = "empty", text = H.NO_COMMANDS[1], how = H.NO_COMMANDS[2] }
    end
    return out
end

function H.Declare(k, diag)
    local api = {}
    local ctx, handle
    local view = { search = "", pick = nil }
    local render
    local id = k.id or ns.id

    local function client() return ctx and ctx.client or k.client end

    local function tree()
        local children = {
            { kind = "header", key = "header", title = H.HEADER,
              search = { placeholder = H.SEARCH, text = view.search, onText = function(text)
                  view.search = type(text) == "string" and text or ""
                  view.pick = nil
                  render()
              end } },
        }
        local list = H.Search(H.PAGES, view.search)
        if #list == 0 then
            children[#children + 1] = { kind = "empty", key = "empty", text = H.NO_MATCH[1], how = H.NO_MATCH[2] }
        else
            local names, sel = {}, 1
            for i, p in ipairs(list) do
                names[i] = p.title
                if p.id == view.pick then sel = i end
            end
            view.pick = list[sel].id
            children[#children + 1] = { kind = "topicList", key = "pages", items = names, selected = sel,
                onSelect = function(i)
                    if list[i] then view.pick = list[i].id end
                    render()
                end }
            children[#children + 1] = { kind = "scroll", key = "body", children = H.Page(list[sel],
                diag and diag.commands, diag and diag.help, id.slash) }
        end
        children[#children + 1] = { kind = "footer", key = "footer", text = H.FOOTER:format(id.slash) }
        return ns.Kit.Window({ id = H.ID, title = id.title .. ": " .. H.HEADER, resizable = true,
            width = H.WIDTH, height = H.HEIGHT, children = children })
    end

    render = function()
        if not handle then return end
        local t, why = tree()
        if not t then
            k.problems:add(H.NAME, "tree", tostring(why))
            return
        end
        handle.update(t)
    end

    function api.Open()
        local c = client()
        if type(c) ~= "table" or type(c.kitWindow) ~= "function" then return false end
        local t, why = tree()
        if not t then
            k.problems:add(H.NAME, "tree", tostring(why))
            return false
        end
        if not handle then
            local point, width, height = ns.Kit.Place(k.store:get("account", H.PATH), t)
            handle = c.kitWindow(H.ID, t, {
                name = id.framePrefix .. "HelpPages",
                point = point, width = width, height = height,
                onMoved = function(at, w, h)
                    if type(at) ~= "table" then return end
                    local ok, err = k.store:set("account", H.PATH,
                        { point = { at[1], at[2], at[3], at[4] }, width = w, height = h })
                    if not ok then k.problems:add(H.NAME, "place", tostring(err)) end
                end,
                onClose = function() end,
                failed = function(err) k.problems:add(H.NAME, "draw", tostring(err)) end,
            })
            if not handle then
                k.problems:add(H.NAME, "window", "the client could not draw the window")
                return false
            end
        else
            handle.update(t)
        end
        handle.show(true)
        return true
    end

    function api.Close()
        if handle then handle.close() end
    end

    function api.Shown()
        return handle ~= nil and handle.shown() == true
    end

    if diag and type(diag.commands) == "table" then
        diag.commands[H.WORD] = function() api.Open() end
        if type(diag.help) == "table" then diag.help[H.WORD] = H.HELP end
    end

    k:Module({
        name = H.NAME,
        needs = { "client", "store" },
        provides = { Open = api.Open, Close = api.Close, Shown = api.Shown },
        start = function(c) ctx = c end,
        stop = function()
            if handle then handle.close() end
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.helpPages = H.Declare(ns, ns.diag)
