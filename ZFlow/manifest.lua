-- The load order of every Lua file in this folder. The TOC is generated from
-- it (tools/zflow-toc.ps1), the offline runner loads from it
-- (tools/zflow-tests.ps1) and the structure check compares the folder with
-- it (tools/zflow-structure.ps1).
--
-- To add a file: put its path, relative to this folder, with forward
-- slashes, where it should load. Kernel first; a feature file may then use
-- anything on ns. A file marked dev = true is loaded by the offline runner
-- but never listed in the TOC. Test files (Tests/**) are not listed here:
-- the runner finds them itself.
return {
    interface = 16001,
    version = "0.1.0",
    files = {
        -- Kernel
        "Core/Identity.lua",
        "Core/Client.lua",
        { "Core/ClientFake.lua", dev = true },
        "Core/Reads.lua",
        "Core/Report.lua",
        "Core/Store.lua",
        "Core/Settings.lua",
        "Core/Bus.lua",
        "Core/Scheduler.lua",
        "Core/Kinds.lua",
        "Core/Guard.lua",
        "Core/Module.lua",
        "Core/Kernel.lua",
        "Core/Diag.lua",
        "Items/Drops.lua",
        "UI/Perf.lua",
        "Core/Sound.lua",
        "UI/MoveGuides.lua",
        "Core/Facts.lua",
        "Core/InviteAdvice.lua",
        "UI/Export.lua",
        "Items/PriceChart.lua",
        "Items/HaveTip.lua",
        "Gear/MerchantButtons.lua",
        "Items/AuctionLog.lua",
        "UI/CopyBox.lua",
        "UI/Advisor.lua",
        "UI/Alerts.lua",
        "UI/Setup.lua",
        "UI/Kit/Parts.lua",
        "UI/Kit/Theme.lua",
        "UI/Kit.lua",
        "UI/KitProbe.lua",

        -- Import
        "Import/FromFlow.lua",
        "Import/Stored.lua",

        -- Settings
        "Settings/Model.lua",
        "Settings/Topics.lua",
        "Settings/Rows.lua",

        -- Items
        "Items/Key.lua",
        "Items/Resources.lua",
        "Items/TooltipHave.lua",
        "Items/Prices.lua",
        "Items/PriceObserve.lua",
        "Items/PriceWatch.lua",
        "Items/Disposition.lua",
        "Items/TooltipDisposition.lua",
        "Items/Bank.lua",
        "Items/Reservations.lua",
        "Items/LootNote.lua",
        "Items/Plan.lua",
        "Items/Present.lua",
        "Items/CraftHint.lua",
        "Items/SkillUps.lua",
        "Items/SkillBoosters.lua",
        "Items/CraftQueue.lua",
        "Items/Sell.lua",
        "Items/Repair.lua",
        "Items/SellView.lua",
        "Items/SellThese.lua",
        "Items/PriceLookup.lua",

        -- Gear
        "Gear/Score.lua",
        "Gear/Read.lua",
        "Gear/CanUse.lua",
        "Gear/Usable.lua",
        "Gear/WeaponSkill.lua",
        "Gear/WeaponSpeed.lua",
        "Gear/Verdict.lua",
        "Gear/Tooltip.lua",
        "Gear/TooltipModule.lua",
        "Gear/MerchantMarks.lua",
        "Gear/RewardMark.lua",
        "Gear/MerchantShow.lua",
        "Gear/RollHint.lua",
        "Gear/Sets.lua",
        "Gear/SetIcons.lua",

        -- Rotation and classes
        "Rotation/Pack.lua",
        "Rotation/Snapshot.lua",
        "Rotation/BuffFood.lua",
        "Rotation/HealItems.lua",
        "Rotation/FoodAdvice.lua",
        "Rotation/Choose.lua",
        "Rotation/KeyPlan.lua",
        "Rotation/Cast.lua",
        "Rotation/Reader.lua",
        "UI/SpellCard.lua",
        "Rotation/Driver.lua",
        "Rotation/KeyFrame.lua",
        "Rotation/Role.lua",
        "Rotation/Spec.lua",
        "Rotation/Fights.lua",
        "UI/FightLog.lua",
        "Classes/Druid.lua",
        "Classes/Hunter.lua",
        "Classes/Mage.lua",
        "Classes/Paladin.lua",
        "Classes/Priest.lua",
        "Classes/Rogue.lua",
        "Classes/Shaman.lua",
        "Classes/Warrior.lua",
        "Classes/Warlock.lua",
        "Rotation/GroupTip.lua",

        -- Navigation
        "Nav/ArrowLayout.lua",
        "Nav/Bearing.lua",
        "Nav/ArrowView.lua",
        "Nav/ArrowMotion.lua",
        "Nav/ArrowStyles.lua",
        "Nav/Guide.lua",
        "Nav/GuideRead.lua",
        "Nav/ViewState.lua",
        "Nav/WaypointStep.lua",
        "Nav/Waypoint.lua",
        "Nav/MinimapPin.lua",
        "Nav/ProfStep.lua",
        "Nav/ProfSeen.lua",
        "Spells/TrainerList.lua",
        "Spells/TrainerListRankUp.lua",
        "Spells/TrainerModule.lua",
        "Spells/ClassQuests.lua",
        "Nav/RoutePlan.lua",
        "Nav/HearthStep.lua",
        "Nav/HearthSeen.lua",
        "Nav/Crossings.lua",
        "Nav/ServiceNearest.lua",
        "Nav/ServiceSeen.lua",
        "Nav/Errand.lua",
        "Nav/RepairStep.lua",
        "Nav/WeaponMasterStep.lua",
        "Nav/WeaponMasterSeen.lua",
        "Nav/QuestSource.lua",
        "Nav/QuestRead.lua",
        "Nav/AddonSources.lua",
        "Nav/Rides.lua",
        "Nav/TravelSpells.lua",
        "Nav/TravelIcon.lua",
        "Nav/Leaving.lua",
        "Nav/FlightPaths.lua",
        "Nav/MapFlights.lua",
        "Nav/TaxiMark.lua",
        "Nav/Flights.lua",
        "Nav/Gates.lua",
        "Nav/Travel.lua",
        "Nav/Legs.lua",
        "Nav/QuestItems.lua",
        "UI/ProfCard.lua",
        "UI/ProfLearn.lua",
        "UI/ProfPick.lua",

        -- On screen (after Nav: the panel uses its saved-point rules)
        "UI/DevPanel.lua",
        "UI/SettingsSlash.lua",
        "UI/SettingsPage.lua",
        "UI/SettingsKeys.lua",
        "UI/SettingsPanel.lua",
        "UI/SettingsWindow.lua",
        "UI/SettingsOptions.lua",
        "UI/Rows.lua",
        "UI/Intro.lua",
        "UI/WindowButtons.lua",
        "UI/ArrowMenu.lua",
        "UI/Feedback.lua",
        "UI/MacroIcons.lua",
        "UI/GameOptions.lua",
        "UI/SellList.lua",
        "UI/BankList.lua",
        "UI/KitHost.lua",
        "Items/Keep.lua",
        "Items/Buyback.lua",
        "Items/RecipeBook.lua",
        "Items/RecipeLearned.lua",
        "Items/ProfRecipes.lua",
        "Items/Goals.lua",
    "UI/Arrow.lua",
    "UI/MinimapPin.lua",
    "UI/RotationIcon.lua",
    "UI/InfoBar.lua",
    "Rotation/Pulse.lua",
    "UI/PlateThreat.lua",
    "UI/PlateCombo.lua",
    "UI/PlateQuests.lua",
    "Rotation/CastEdge.lua",
    "Rotation/Audit.lua",
    "Rotation/FormSpells.lua",
    "Rotation/OwnCasts.lua",
    "Rotation/Combo.lua",
    "Fight/Choices.lua",
    "Rotation/Queue.lua",
    "UI/RotationQueue.lua",
    "Items/Banker.lua",
    "Items/Posting.lua",
    "Items/Trader.lua",
    "Nav/Try.lua",
    { "Core/Capture.lua", dev = true },
    { "Core/CaptureEvidence.lua", dev = true },
    "Rotation/Gather.lua",
    -- P-PARTY: your group's buffs and dispels, look only (after GroupTip and Choose).
    "Rotation/Group.lua",
    -- N63: heal and cures on the unit under your mouse, off by default.
    "Rotation/Mouseover.lua",
    "Rotation/CareKeys.lua",
    -- N41 key controls and S23 click-casting check (P-KEYS slice B).
    "Rotation/KeyControls.lua",
    "UI/ClickCheck.lua",
    -- S15 click slots and S29 move handle (P-KEYS slice C).
    "UI/MoveHandle.lua",
    "Rotation/ClickSlots.lua",
    -- Section 285 item 2b: the Flow button and the self button on screen.
    "Rotation/FlowButton.lua",
    -- N1, N2, N20, N5 key actions (P-KEYS slice D).
    "Rotation/KeyActions.lua",
    -- N39, N40, N26, N27: auto attack, the spells list and the placed notice (P-KEYS slice E).
    "Rotation/SpellKeys.lua",
    -- N64: the weapon enchant reminder, a line in chat only (after Group).
    "Rotation/Enchant.lua",
    -- N55: the boss loot panel, look only (after Gear, Items/Drops and the classes).
    "UI/BossLoot.lua",
    -- G60: NPC words read aloud, off by default (after the settings page).
    "UI/NpcSpeech.lua",
    -- G55: the staged reveal for a new player (after the arrow, the icon, the advisor and the intro).
    "UI/Reveal.lua",
    -- N70: settings export and import as data (after Export, Diag and the settings page).
    "UI/SettingsShare.lua",
    -- Lead section 303: the Dungeon Quests pane's data (pure).
    "Nav/DungeonStates.lua",
    -- Lead section 303: the Dungeon Quests reader (Questie at runtime).
    "Nav/DungeonRead.lua",
    -- Lead section 305: boss kills as the client reports them (after Diag).
    "Nav/BossKills.lua",
    -- Lead section 318: the Dungeon Quests window, on the kit (after Kit and the dungeon data).
    "UI/DungeonWindow.lua",
    "UI/HelpPages.lua",
    "UI/SetupList.lua",
    -- P-TRIP (S43): quest spots learned from the player's own play (after QuestRead and Diag).
    "Nav/QuestSpots.lua",
    -- P-TRIP (S39/S43/S40): quest routes and dungeon runs for the arrow (after RoutePlan, QuestSpots).
    "Nav/TripRoute.lua",
    -- Lead DISPATCH section 340: the minimap button's rim math (pure), then the button.
    "UI/MinimapPlace.lua",
    "UI/MinimapButton.lua",
    -- G38, G47, G22 (P-NAV): learned cave trails, pointing at a party member,
    -- the nodes you gathered (after the arrow, Waypoint and Gather).
    "Nav/Trails.lua",
    "Nav/Follow.lua",
    "Nav/Nodes.lua",
    -- N60a: copy chat text and clickable web addresses in chat (after the settings page).
    "UI/Chat.lua",
    -- G48 (P-TRIP): the party route over add-on messages (after TripRoute).
    "Nav/PartyRoute.lua",
    -- P-EVIDENCE+ (sections 252, 262): look-only capture fields saved under diag (after Diag).
    "Core/AutoEvidence.lua",
    -- P-TRIP slice 1: the trip list of stops for the route (after TripRoute, Errand, DungeonRead).
    "Nav/Trip.lua",
    -- G43 (P-TRIP): the route tracker window and the current step's map pin (after Trip, TripRoute, the kit).
    "UI/RouteTracker.lua",
    -- P-QUEST (lead section 354 item 4): quest advice text (after QuestRead and the advisor).
    "Nav/QuestAdvice.lua",
    -- R7 (sections 387, 388 b): spells to train, as advisor prompts (after the class packs and the advisor).
    "Spells/TrainAdvice.lua",
    -- P-COACH C1 (section 382): the profession plan, steps toward the next point (after RecipeBook, HaveTip, Prices, ProfStep).
    "Items/ProfPlan.lua",
    -- P-COACH C3 (section 382): where the plan's short materials come from (after ProfPlan, Prices).
    "Items/ProfSources.lua",
    -- Section 387: the next-step panel docked under the game's profession window (after ProfPlan, ProfSources, KitHost).
    "UI/ProfDock.lua",
    -- Lead section 382 (C2 P-COACH): one profession step for the needle (after ProfStep, Legs, ProfPlan, ProfSources).
    "Nav/ProfFeed.lua",
    -- G46 (lead section 391 item 2): when hearthing saves the walk, and where to set home (after Trip, TripRoute).
    "Nav/HearthAdvice.lua",
    -- S35 (section 395 item 3): gate words for trip legs (after Gates, Trip).
    "Nav/GateWords.lua",
    -- S32: boat and zeppelin dock names and wait words (Crossings calls them at run time).
    "Nav/CrossingWords.lua",
    -- S38 (lead section 395 item 6): activities and route lanes (after Trip, Nodes).
    "Nav/Activities.lua",
    -- G57: lite mode, the perf.lite row and the lite word (after Diag and every module it switches off).
    "UI/Lite.lua",
    },
}
