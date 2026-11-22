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
        "UI/CopyBox.lua",
        "UI/Advisor.lua",
        "UI/Setup.lua",

        -- Import
        "Import/FromFlow.lua",
        "Import/Stored.lua",

        -- Settings
        "Settings/Model.lua",

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
        "Items/LootNote.lua",
        "Items/Plan.lua",
        "Items/Present.lua",
        "Items/CraftHint.lua",
        "Items/Sell.lua",
        "Items/Repair.lua",
        "Items/SellView.lua",
        "Items/PriceLookup.lua",

        -- Gear
        "Gear/Score.lua",
        "Gear/Read.lua",
        "Gear/CanUse.lua",
        "Gear/Usable.lua",
        "Gear/WeaponSpeed.lua",
        "Gear/Verdict.lua",
        "Gear/Tooltip.lua",
        "Gear/TooltipModule.lua",
        "Gear/MerchantMarks.lua",
        "Gear/MerchantShow.lua",
        "Gear/RollHint.lua",

        -- Rotation and classes
        "Rotation/Pack.lua",
        "Rotation/Snapshot.lua",
        "Rotation/Choose.lua",
        "Rotation/KeyPlan.lua",
        "Rotation/Cast.lua",
        "Rotation/Reader.lua",
        "UI/SpellCard.lua",
        "Rotation/Driver.lua",
        "Rotation/KeyFrame.lua",
        "Rotation/Role.lua",
        "Rotation/Fights.lua",
        "UI/FightLog.lua",
        "Classes/Druid.lua",
        "Classes/Paladin.lua",
        "Classes/Priest.lua",
        "Classes/Shaman.lua",

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
        "Nav/RoutePlan.lua",
        "Nav/HearthStep.lua",
        "Nav/HearthSeen.lua",
        "Nav/ServiceNearest.lua",
        "Nav/ServiceSeen.lua",
        "Nav/Errand.lua",
        "Nav/QuestSource.lua",
        "Nav/QuestRead.lua",
        "UI/ProfCard.lua",

        -- On screen (after Nav: the panel uses its saved-point rules)
        "UI/DevPanel.lua",
        "UI/SettingsSlash.lua",
        "UI/SettingsPage.lua",
        "UI/SettingsPanel.lua",
        "UI/SettingsOptions.lua",
        "UI/Rows.lua",
        "UI/Intro.lua",
        "UI/WindowButtons.lua",
        "UI/ArrowMenu.lua",
        "UI/SellList.lua",
        "UI/BankList.lua",
        "Items/Keep.lua",
    "UI/Arrow.lua",
    "UI/MinimapPin.lua",
    "UI/RotationIcon.lua",
    },
}
