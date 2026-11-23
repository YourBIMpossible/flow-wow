-- The window kit's one theme file (lead section 303 item 3): every size,
-- colour, font and Blizzard part name a kit window uses. The owner's later
-- art pass changes the look of every window here and nowhere else.
--
-- Blizzard-native: the game's own templates, font objects, icons and
-- GameTooltip, asked for by name. No art file of ours, of Blizzard's or of
-- another add-on is in this add-on. The checklist followed is the SaneUI
-- project's Doc/guides/gui-development.md (github.com/GlennDrescher/SaneUI,
-- MIT): find the nearest Blizzard window and build from its templates,
-- fonts by font object, close on Escape, keep the window on screen, and
-- say of each window whether it was tried in the game. None of its code is
-- here. Tried in the game: not yet.
--
-- Pure data: no client and no kernel. UI/Kit.lua hands it out as Kit.look.
local _, ns = ...

-- Every size, colour, font and stock art name a kit window uses. The client
-- reads it; no window and no part writes a colour or a size of its own.
-- Each art entry is the name tried first and what is drawn when this client
-- does not have it. None of the art names has been seen in game on 16001
-- except those Core/Client.lua already used: first guesses. A template is
-- asked for by a protected create when its part is made: the part is the
-- game's own when that works, else the kit's plain panel (lead sections 297
-- item 4 and 303). A picture cannot be asked that way, so `unproven` names
-- the pictures not yet seen on 16001: the plain form is drawn for each
-- until its key is taken out.
ns.KitTheme = {
    size = {
        pad = 12, gap = 8, gapSmall = 4,
        title = 24,
        rowHeight = 28, rowHeightDesc = 42, lineHeight = 24,
        icon = 20, coin = 12,
        header = 32, tab = 24, section = 24,
        topicWidth = 180, topicRow = 24,
        -- Lead section 340: the pane's page heading (the retail Settings
        -- window's category title).
        pageTitle = 36,
        controlColumn = 200,
        button = 22, buttonMin = 96, buttonPad = 24,
        check = 24, search = 180, scrollBar = 18,
        footer = 36, grip = 16, numberValue = 60,
        wheelLines = 3,
        edge = 1, gripCorner = 12, choiceButtons = 3,
    },
    color = {
        accent = { 1, 0.82, 0, 1 },
        text = { 1, 1, 1, 1 },
        textDim = { 0.75, 0.75, 0.75, 1 },
        textOff = { 0.5, 0.5, 0.5, 1 },
        good = { 0.3, 1, 0.4, 1 },
        warn = { 1, 0.62, 0, 1 },
        bad = { 1, 0.25, 0.25, 1 },
        fill = { 0.05, 0.05, 0.05, 0.92 },
        inset = { 0, 0, 0, 0.35 },
        edge = { 0.4, 0.4, 0.4, 1 },
        divider = { 1, 1, 1, 0.12 },
        stripe = { 1, 1, 1, 0.04 },
        hover = { 1, 1, 1, 0.08 },
        selected = { 1, 0.82, 0, 0.18 },
        -- The coin letters, drawn when a coin icon is missing.
        gold = { 1, 0.82, 0, 1 },
        silver = { 0.78, 0.78, 0.78, 1 },
        copper = { 0.72, 0.45, 0.2, 1 },
    },
    -- How strongly a stock highlight picture is drawn (blended in).
    alpha = { rowHighlight = 0.5, topicHighlight = 0.6 },
    coinLetter = { gold = "g", silver = "s", copper = "c" },
    -- The mark at the right of a section that folds.
    foldMark = { open = "-", closed = "+" },
    unproven = {
        rowHighlight = true, topicHighlight = true, iconBorder = true,
        grip = true, gripOver = true, gripDown = true,
    },
    font = {
        title = "GameFontNormal",
        heading = "GameFontNormal",
        label = "GameFontHighlight",
        small = "GameFontHighlightSmall",
        off = "GameFontDisableSmall",
        big = "GameFontNormalLarge",
        -- Lead section 340, first guess on 16001; the plain form is big.
        pageTitle = "GameFontHighlightHuge",
    },
    -- Pictures a window puts on its own rows, by what they mean: a window
    -- file takes them from here (Kit.look.icon.questInLog) and names no
    -- picture itself. The game's own quest marks. First guesses, none seen
    -- in game on 16001; a picture the client lacks leaves the row without
    -- an icon.
    icon = {
        questInLog = "Interface\\GossipFrame\\ActiveQuestIcon",
        questAvailable = "Interface\\GossipFrame\\AvailableQuestIcon",
        questLater = "Interface\\GossipFrame\\IncompleteQuestIcon",
        questNotForYou = "Interface\\Buttons\\UI-GroupLoot-Pass-Up",
    },
    art = {
        -- Pictures only. The game's templates are named in Core/Client.lua
        -- alone (its kitWindow), each keyed to its row of UI/Kit/Parts.lua.
        rowHighlight = "Interface\\QuestFrame\\UI-QuestTitleHighlight",
        topicHighlight = "Interface\\Buttons\\UI-Listbox-Highlight",
        iconBorder = "Interface\\Buttons\\UI-Quickslot2",
        iconMissing = "Interface\\Icons\\INV_Misc_QuestionMark",
        grip = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up",
        gripOver = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight",
        gripDown = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down",
        gold = "Interface\\MoneyFrame\\UI-GoldIcon",
        silver = "Interface\\MoneyFrame\\UI-SilverIcon",
        copper = "Interface\\MoneyFrame\\UI-CopperIcon",
    },
}
