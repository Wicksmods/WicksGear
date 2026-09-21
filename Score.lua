-- Wick's Gear
-- Score.lua: what a piece is worth, and whether you can wear it.
--
-- The data file carries item ids and where they come from. Everything
-- else is asked of the client: names, icons, stats, what slot it goes in.
-- That means nothing here can go stale against a patch, and it means the
-- numbers shown are the ones this server is actually using rather than
-- the ones a website had when somebody scraped it.
--
-- Items are not in memory until asked for. C_Item.GetItemInfo returns
-- nothing for an item the client has never seen, so anything wanting
-- stats has to request a load and wait.

local ADDON, ns = ...
local Core = WickCore

local S = {}
ns.Score = S

local WEAPON_CLASS, ARMOR_CLASS = 2, 4

-- Equip locations to the inventory slot holding them, so a candidate can
-- be set against what you are already wearing.
local EQUIP_SLOT = {
    INVTYPE_HEAD = 1, INVTYPE_NECK = 2, INVTYPE_SHOULDER = 3, INVTYPE_BODY = 4,
    INVTYPE_CHEST = 5, INVTYPE_ROBE = 5, INVTYPE_WAIST = 6, INVTYPE_LEGS = 7,
    INVTYPE_FEET = 8, INVTYPE_WRIST = 9, INVTYPE_HAND = 10, INVTYPE_FINGER = 11,
    INVTYPE_TRINKET = 13, INVTYPE_CLOAK = 15, INVTYPE_WEAPON = 16,
    INVTYPE_2HWEAPON = 16, INVTYPE_WEAPONMAINHAND = 16, INVTYPE_SHIELD = 17,
    INVTYPE_WEAPONOFFHAND = 17, INVTYPE_HOLDABLE = 17, INVTYPE_RANGED = 18,
    INVTYPE_RANGEDRIGHT = 18, INVTYPE_THROWN = 18, INVTYPE_RELIC = 18,
}

-- Friendly names, in the order a character sheet reads.
S.SLOT_NAME = {
    [1] = "Head", [2] = "Neck", [3] = "Shoulder", [5] = "Chest", [6] = "Waist",
    [7] = "Legs", [8] = "Feet", [9] = "Wrist", [10] = "Hands", [11] = "Finger",
    [13] = "Trinket", [15] = "Back", [16] = "Weapon", [17] = "Off hand",
    [18] = "Ranged",
}
S.SLOT_ORDER = { 1, 2, 3, 15, 5, 9, 10, 6, 7, 8, 11, 13, 16, 17, 18 }

local CASTER_ROLES = {
    PALADIN_HOLY = true, SHAMAN_CASTER = true, DRUID_CASTER = true,
    PRIEST = true, MAGE = true, WARLOCK = true,
}

-- ============================================================
-- Which weights apply
-- ============================================================

-- Some classes play two ways that want opposite gear, so the profile
-- carries a choice. The default is whatever that class mostly does while
-- levelling.
S.ROLES = {
    WARRIOR = { "WARRIOR", "WARRIOR_PROT" },
    PALADIN = { "PALADIN", "PALADIN_HOLY" },
    SHAMAN  = { "SHAMAN", "SHAMAN_CASTER" },
    DRUID   = { "DRUID", "DRUID_CASTER" },
}

function S:ClassKey()
    local _, class = UnitClass("player")
    local choice = ns.db().role
    local options = self.ROLES[class]
    if options then
        for _, o in ipairs(options) do
            if o == choice then return o end
        end
        return options[1]
    end
    return class
end

function S:Weights()
    return ns.WEIGHTS[self:ClassKey()]
end

function S:DpsRate()
    local key = self:ClassKey()
    if CASTER_ROLES[key] then return ns.DPS_RATE.caster end
    if key == "HUNTER" then return ns.DPS_RATE.hunter end
    return ns.DPS_RATE.melee
end

-- ============================================================
-- Loading
-- ============================================================

-- Asking for item data
-- ============================================================
-- The client answers these from the server, and it throttles. Asking
-- for all two hundred and seventy at the moment the window opens got
-- most of them dropped and left rows reading "loading..." a minute
-- later, which is worse than asking slowly.
--
-- So they go in a queue and leave a handful at a time. Nothing waits
-- for the whole set: each answer redraws whatever is on screen, so the
-- list fills in as it arrives.

local queue, queued, pumping = {}, {}, false
local BATCH, EVERY = 12, 0.2

local function cached(id)
    if C_Item.IsItemDataCachedByID and C_Item.IsItemDataCachedByID(id) then
        -- Cached is not the same as answerable: ask for the name too,
        -- since that is what the list actually shows.
        return C_Item.GetItemInfo(id) ~= nil
    end
    return C_Item.GetItemInfo(id) ~= nil
end
S.Cached = cached

local function pump()
    local sent = 0
    while sent < BATCH do
        local id = table.remove(queue)
        if not id then break end
        queued[id] = nil
        if not cached(id) then
            pcall(C_Item.RequestLoadItemDataByID, id)
            sent = sent + 1
        end
    end
    if #queue > 0 then
        C_Timer.After(EVERY, pump)
    else
        pumping = false
    end
end

-- Ask for these, eventually. Returns how many are still unknown, so a
-- caller can say so rather than looking broken.
function S:Want(ids)
    local missing = 0
    for _, id in ipairs(ids) do
        if not cached(id) then
            missing = missing + 1
            if not queued[id] then
                queued[id] = true
                queue[#queue + 1] = id
            end
        end
    end
    if missing > 0 and not pumping then
        pumping = true
        C_Timer.After(0, pump)
    end
    return missing
end

-- Put what is on screen at the front, so looking at a dungeon fetches
-- that dungeon before the thirteen you are not looking at.
function S:WantFirst(ids)
    for _, id in ipairs(ids) do
        if not cached(id) and not queued[id] then
            queued[id] = true
            table.insert(queue, id)      -- the end is the front: pump pops
        end
    end
    if not pumping then
        pumping = true
        C_Timer.After(0, pump)
    end
end

-- ============================================================
-- Reading an item
-- ============================================================

-- Names and links without waiting on the server
-- ============================================================
-- GetItemInfo needs the item to have arrived from the server, and on
-- this beta a lot of them simply do not. Two ways round it, both
-- answered out of the client's own files:
--
--   GetItemNameByID gives the name on its own.
--   "item:1234" is a valid hyperlink string, and the stat reader takes
--   a string, so stats can be read without a full item ever landing.
--
-- Whatever the real link turns up, it is preferred, since it carries
-- enchants and suffixes. These are the floor, not the ceiling.

function S:LinkFor(id)
    local ok, _, link = pcall(C_Item.GetItemInfo, id)
    if ok and link then return link end
    return "item:" .. tostring(id)
end

function S:NameFor(id)
    if C_Item.GetItemNameByID then
        local ok, name = pcall(C_Item.GetItemNameByID, id)
        if ok and type(name) == "string" and name ~= "" then return name end
    end
    local ok, name = pcall(C_Item.GetItemInfo, id)
    if ok and type(name) == "string" and name ~= "" then return name end
    -- The client has never met this item. Fall back to what shipped.
    local entry = ns.ENTRY and ns.ENTRY[id]
    return entry and entry.name ~= "" and entry.name or nil
end

-- Stats for an id, the client's answer preferred over the shipped one
-- because the client is the one this server is actually using.
function S:StatsOf(id)
    local live = self:NormalStats(self:LinkFor(id))
    if next(live) ~= nil then return live, true end
    local entry = ns.ENTRY and ns.ENTRY[id]
    if entry and entry.stats then
        local copy = {}
        for k, v in pairs(entry.stats) do copy[k] = v end
        return copy, false
    end
    return {}, false
end

function S:Info(id)
    -- GetItemInfoInstant answers without the item being cached, which is
    -- enough to know the slot and whether the class may use it.
    local _, _, _, equipLoc, icon, classID, subClassID = C_Item.GetItemInfoInstant(id)
    if not equipLoc then return nil end
    return {
        id = id,
        equipLoc = equipLoc,
        slot = EQUIP_SLOT[equipLoc],
        icon = icon,
        classID = classID,
        subClassID = subClassID,
    }
end

function S:Usable(info)
    local prof = ns.PROFICIENCY[self:ClassKey()]
    if not prof or not info then return true end
    local function has(list, v)
        for _, n in ipairs(list) do if n == v then return true end end
        return false
    end
    if info.classID == ARMOR_CLASS then
        -- Cloaks, rings, necks and trinkets carry a negative subclass and
        -- no restriction. Only a positive one is a real armour type.
        if not info.subClassID or info.subClassID <= 0 then return true end
        if not has(prof.armor, info.subClassID) then return false end
        -- Mail and plate are trained at forty. Telling a level twenty
        -- hunter to go and find mail is worse than saying nothing.
        local at = prof.armorAt and prof.armorAt[info.subClassID]
        if at and (UnitLevel("player") or 1) < at then return false end
        return true
    end
    if info.classID == WEAPON_CLASS then
        return has(prof.weapon, info.subClassID)
    end
    return true
end

-- Points, in units of the class's primary stat.
--
-- Everything arrives here in our own short stat names, whether it came
-- from the client or from the shipped fallback, so there is one place
-- that knows what a stat is worth.
local WEIGHT_OF = { str = "strength", agi = "agility", sta = "stamina",
                    int = "intellect", spi = "spirit", armor = "armor" }

function S:Weigh(short, link, w)
    local total, parts = 0, {}
    for _, key in ipairs(self.STAT_ORDER) do
        local value = short[key]
        local weight = value and w[WEIGHT_OF[key]]
        if weight and weight ~= 0 then
            total = total + value * weight
            parts[#parts + 1] = ("%s %d"):format(key, value)
        end
    end

    -- A weapon's damage swamps its stat line, so it is converted rather
    -- than left out. For a caster the weapon is a stat stick and the
    -- rate is set low to say so.
    if link then
        local speed, lo, hi = self:WeaponDamage(link)
        if speed and speed > 0 then
            local dps = ((lo + hi) / 2) / speed
            total = total + dps * self:DpsRate()
            table.insert(parts, 1, ("%.1f dps"):format(dps))
        end
    end

    return total, table.concat(parts, ", ")
end

function S:Value(link, id)
    local w = self:Weights()
    if not w then return 0, nil end
    if id then return self:Weigh((self:StatsOf(id)), link, w) end
    if not link then return 0, nil end
    return self:Weigh(self:NormalStats(link), link, w)
end

function S:WeaponDamage(link)
    local ok, lo, hi, _, _, _, speed = pcall(C_Item.GetItemInfo, link)
    if not ok then return nil end
    -- GetItemInfo does not hand back damage; the tooltip does. Read the
    -- weapon's speed and damage from the item's own data instead.
    local d = C_TooltipInfo and C_TooltipInfo.GetHyperlink and C_TooltipInfo.GetHyperlink(link)
    if not d or not d.lines then return nil end
    local minD, maxD, spd
    for _, line in ipairs(d.lines) do
        local text = line.leftText or ""
        local a, b = text:match("(%d+)%s*%-%s*(%d+)%s+Damage")
        if a then minD, maxD = tonumber(a), tonumber(b) end
        local s = (line.rightText or ""):match("Speed%s+([%d%.]+)")
            or text:match("Speed%s+([%d%.]+)")
        if s then spd = tonumber(s) end
    end
    if minD and spd then return spd, minD, maxD or minD end
    return nil
end

-- The item's own stats, under names the paperdoll can subtract.
local STAT_KEY = {
    ITEM_MOD_STRENGTH_SHORT  = "str",
    ITEM_MOD_AGILITY_SHORT   = "agi",
    ITEM_MOD_STAMINA_SHORT   = "sta",
    ITEM_MOD_INTELLECT_SHORT = "int",
    ITEM_MOD_SPIRIT_SHORT    = "spi",
    RESISTANCE0_NAME         = "armor",
}
S.STAT_ORDER = { "str", "agi", "sta", "int", "spi", "armor" }
S.STAT_LABEL = { str = "Strength", agi = "Agility", sta = "Stamina",
                 int = "Intellect", spi = "Spirit", armor = "Armor" }

function S:NormalStats(link)
    local out = {}
    if not link then return out end
    local stats = C_Item.GetItemStats(link)
    if not stats then return out end
    for key, value in pairs(stats) do
        local short = STAT_KEY[key]
        if short and type(value) == "number" then out[short] = value end
    end
    return out
end

function S:EquippedStats(slot)
    if not slot then return {} end
    return self:NormalStats(GetInventoryItemLink("player", slot))
end

function S:EquippedValue(slot)
    if not slot then return 0, nil end
    local link = GetInventoryItemLink("player", slot)
    if not link then return 0, nil end
    return self:Value(link)
end

-- ============================================================

function S:Init()
    -- Two events, because the two dialects announce this differently and
    -- either may be the one this build sends.
    ns.RegisterEvents({ "GET_ITEM_INFO_RECEIVED" })
    ns:On("ITEM_DATA_LOAD_RESULT", function() ns.UI:ItemArrived() end)
    ns:On("GET_ITEM_INFO_RECEIVED", function() ns.UI:ItemArrived() end)
    -- Redraw the paperdoll when the character underneath it changes.
    ns.RegisterEvents({ "PLAYER_EQUIPMENT_CHANGED", "UNIT_STATS" })
    local function changed() if ns.Doll and ns.Doll.pane then ns.Doll:Refresh() end end
    ns:On("PLAYER_EQUIPMENT_CHANGED", changed)
    ns:On("UNIT_STATS", function(_, unit) if unit == "player" then changed() end end)
end
