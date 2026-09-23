-- Wick's Gear
-- Core.lua: namespace, events, slash command, options.
--
-- Two jobs in one window. Upgrades answers "what should I be chasing",
-- by scoring every levelling drop against what you are wearing. Browse
-- answers "what is in there", dungeon by dungeon.
--
-- The data file holds item ids and where they come from, nothing else.
-- Names, icons and stats are asked of the client, so the numbers are the
-- ones this server is using rather than the ones a website had.

local ADDON, ns = ...
local Core = WickCore
if not Core then
    -- WickCore is missing or switched off.
    --
    -- The TOC asks for it with OptionalDeps rather than Dependencies on
    -- purpose. A hard dependency makes the client refuse to load this addon
    -- at all, so nothing of ours runs and the player is told nothing beyond
    -- a greyed line in the AddOns list. Loading anyway lets us say what is
    -- wrong and where to get it.
    --
    -- One line for the lot of them, not one per addon: with the whole suite
    -- installed and WickCore switched off, a line each would be a wall.
    local need = _G.WicksNeedCore
    if not need then
        need = {}
        _G.WicksNeedCore = need
        local f = CreateFrame("Frame")
        f:RegisterEvent("PLAYER_LOGIN")
        f:SetScript("OnEvent", function()
            table.sort(need)
            print(("|cff4FC778Wick's Mods|r: %s %s WickCore, which is not installed or not switched on. It is in the same download as the rest of the suite: |cffD4C8A1wicksmods.com|r")
                :format(table.concat(need, ", "), #need == 1 and "needs" or "need"))
        end)
    end
    need[#need + 1] = "Wick's Gear"
    return
end
ns.version = "0.9.0"

local PROFILE_DEFAULTS = {
    window   = {},
    role     = nil,      -- set for the classes that play two ways
    maxLevel = 0,        -- 0 means "whatever I could wear now"
    hideWorn = false,    -- drop anything not an upgrade
    onlyEquippable = false,  -- browse: hide what this class cannot wear
}

local A = Core:NewAddon("WicksGear", {
    title    = "Wick's Gear",
    version  = ns.version,
    savedVar = "WicksGearSaved",
    defaults = { profile = PROFILE_DEFAULTS, global = {} },
})
ns.A = A

local events = {}
function ns:On(event, fn)
    events[event] = events[event] or {}
    table.insert(events[event], fn)
end

local frame = CreateFrame("Frame", "WicksGearEvents")
ns.eventFrame = frame
frame:SetScript("OnEvent", function(_, event, ...)
    if not events[event] then return end
    for _, fn in ipairs(events[event]) do
        local ok, err = pcall(fn, event, ...)
        if not ok then A:Print(("error in %s: %s"):format(event, tostring(err))) end
    end
end)
function ns.RegisterEvents(list)
    for _, ev in ipairs(list) do pcall(frame.RegisterEvent, frame, ev) end
end

function ns.db() return A.db and A.db.profile or {} end

-- id -> the entry that carries its fallback name and stats, so anything
-- can reach them without walking every dungeon again.
ns.ENTRY = {}

-- Every source, not only the dungeons. The fallback exists for items the
-- client has never met, and a crafted piece or a quest reward from a zone
-- the character has not been to is exactly that: leaving them out meant
-- the two newest sources had no names, no tooltips and no chat links.
local function index(tbl, key, nested)
    for group, rows in pairs(tbl or {}) do
        for _, it in ipairs(nested and rows.items or rows) do
            -- Where it came from is part of describing it, and the data
            -- files are keyed the other way round.
            it[key] = group
            ns.ENTRY[it.id] = it
        end
    end
end
index(ns.DUNGEONS, "dungeon", true)
index(ns.CRAFTED, "profession", false)
index(ns.QUESTS, "zone", false)

-- Every id in the data, once, for preloading.
function ns.AllItemIDs()
    local ids = {}
    -- ENTRY is already every item from every source, keyed once.
    for id in pairs(ns.ENTRY) do ids[#ids + 1] = id end
    return ids
end

function A:OnEnable()
    ns.Score:Init()
    ns.UI:Init()

    self:RegisterLauncher({
        onClick = function(_, button)
            if button == "RightButton" then ns.UI:Toggle("browse") else ns.UI:Toggle("upgrades") end
        end,
        tooltip = function(tt)
            tt:AddLine(Core.Chrome:TitleMarkup("Wick's Gear"))
            tt:AddLine("Left-click: upgrades   Right-click: browse", 0.5, 0.5, 0.5)
        end,
    })

    self:RegisterOptions(function(page, addon)
        local O = Core.Options
        local db = addon.db.profile
        local y = O:Heading(page, "Scoring", 0)
        y = O:Note(page, "Every piece is scored in points of your class's main stat, using weights tuned for levelling rather than for raiding. Stamina and Spirit count for more here than any endgame list would give them, because what slows levelling down is downtime rather than a missing point of damage.", y)

        local options = ns.Score.ROLES[select(2, UnitClass("player"))]
        if options then
            y = O:Heading(page, "How you play", y - 6)
            for _, key in ipairs(options) do
                local label = key:gsub("_", " "):lower():gsub("^%l", string.upper)
                y = O:Check(page, label,
                    function() return ns.Score:ClassKey() == key end,
                    function(v) if v then db.role = key; ns.UI:Refresh() end end, y)
            end
            y = O:Note(page, "These want opposite gear, so pick the one you are actually levelling as.", y)
        end

        y = O:Heading(page, "The list", y - 6)
        y = O:Check(page, "Only show what would be an upgrade",
            function() return db.hideWorn == true end,
            function(v) db.hideWorn = v; ns.UI:Refresh() end, y)
        y = O:Note(page, ("Reading %d dungeons collected %s. Re-run the scrapers in WickSuite as the beta fills in: the later dungeons are thin because Wowhead's Forever data grows from what players actually see.")
            :format(#ns.DUNGEON_ORDER, ns.COLLECTED or "recently"), y)

        y = O:Button(page, "Open", function() ns.UI:Toggle() end, y - 4, 90)
        y = O:ProfileSection(page, addon, y - 8)
    end)
end

SLASH_WICKSGEAR1 = "/wgear"
SLASH_WICKSGEAR2 = "/wbis"
SlashCmdList.WICKSGEAR = function(input)
    local cmd = tostring(input or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if cmd == "" or cmd == "toggle" then ns.UI:Toggle()
    elseif cmd == "browse" then ns.UI:Toggle("browse")
    elseif cmd == "crafted" then ns.UI:Toggle("browse"); ns.UI:SetSource("crafted")
    elseif cmd == "quests" then ns.UI:Toggle("browse"); ns.UI:SetSource("quests")
    elseif cmd == "sets" then ns.UI:Toggle("browse"); ns.UI:SetSource("sets")
    elseif cmd == "upgrades" or cmd == "bis" then ns.UI:Toggle("upgrades")
    elseif cmd == "data" then
        -- What actually loaded. A view that comes up empty looks the same
        -- whether the table is missing, the order list is missing, or the
        -- file never loaded at all, and those want different fixes.
        local function count(t)
            if type(t) ~= "table" then return -1 end
            local n = 0
            for _ in pairs(t) do n = n + 1 end
            return n
        end
        A:Print(("dungeons: %d groups, order %d"):format(
            count(ns.DUNGEONS), count(ns.DUNGEON_ORDER)))
        A:Print(("crafted:  %d groups, order %d"):format(
            count(ns.CRAFTED), count(ns.CRAFTED_ORDER)))
        A:Print(("quests:   %d groups, order %d"):format(
            count(ns.QUESTS), count(ns.QUESTS_ORDER)))
        A:Print(("entries indexed: %d"):format(count(ns.ENTRY)))
        local f = ns.UI and ns.UI.lastFill
        if f then
            A:Print(("last draw: %s, %d groups, %d rows, %d open%s"):format(
                f.source, f.groups, f.rows, f.open,
                f.filtered and ", equippable only" or ""))
        else
            A:Print("last draw: the browse list has not been drawn yet")
        end
        if type(ns.CRAFTED) == "table" then
            for k, v in pairs(ns.CRAFTED) do
                A:Print(("   %s: %d"):format(tostring(k), count(v)))
            end
        end
    elseif cmd == "options" or cmd == "config" then A:OpenOptions()
    elseif cmd:match("^link") then
        -- What a link looks like on this build, ours beside the client's.
        local id = tonumber(cmd:match("^link%s+(%d+)") or "")
        A:Print(("this build uses %s fields in an item link"):format(
            tostring(ns.Score:LinkFields() or "an unknown number of")))
        local worn
        for slot = 1, 19 do
            local ok, l = pcall(GetInventoryItemLink, "player", slot)
            if ok and l then worn = l break end
        end
        if worn then A:Print("yours:  " .. worn:gsub("|", "||")) end
        if id then
            local link, source = ns.Score:ChatLink(id)
            A:Print(("ours:   %s  (%s)"):format(link and link:gsub("|", "||") or "none", tostring(source)))
        else
            A:Print("give an id to compare: /wgear link 279899")
        end
    else
        A:Print("commands:")
        A:Print("  /wgear            what to chase, scored against what you wear")
        A:Print("  /wgear browse     what drops where, dungeon by dungeon")
        A:Print("  /wgear crafted    what the professions make")
        A:Print("  /wgear quests     quest rewards worth the trip")
        A:Print("  /wgear sets       gear grouped by the set it belongs to")
        A:Print("  /wgear data       what data actually loaded")
        A:Print("  /wgear options    weights and what counts as your role")
        A:Print("  /wgear link <id>  what an item link looks like here, ours beside the client's")
    end
end

function WicksGear_Toggle() if ns.UI then ns.UI:Toggle() end end
