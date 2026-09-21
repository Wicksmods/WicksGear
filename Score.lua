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

local pending, waiting = {}, false

-- Ask the client for everything we are about to score. Items arrive over
-- several frames, so the caller is told once the queue has drained.
function S:Preload(ids, onDone)
    local need = 0
    for _, id in ipairs(ids) do
        if not C_Item.IsItemDataCachedByID(id) then
            need = need + 1
            pending[id] = true
            C_Item.RequestLoadItemDataByID(id)
        end
    end
    if need == 0 then
        if onDone then onDone() end
        return
    end
    self.onDone = onDone
    if not waiting then
        waiting = true
        ns.RegisterEvents({ "ITEM_DATA_LOAD_RESULT" })
    end
    -- A backstop: an id the server will not answer for would otherwise
    -- leave the panel waiting forever.
    C_Timer.After(3, function()
        if S.onDone then
            local cb = S.onDone
            S.onDone = nil
            wipe(pending)
            cb()
        end
    end)
end

function S:OnItemLoaded(id)
    pending[id] = nil
    if next(pending) == nil and self.onDone then
        local cb = self.onDone
        self.onDone = nil
        cb()
    end
end

-- ============================================================
-- Reading an item
-- ============================================================

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
        return has(prof.armor, info.subClassID)
    end
    if info.classID == WEAPON_CLASS then
        return has(prof.weapon, info.subClassID)
    end
    return true
end

-- Points, in units of the class's primary stat.
function S:Value(link)
    if not link then return 0, nil end
    local stats = C_Item.GetItemStats(link)
    if not stats then return 0, nil end
    local w = self:Weights()
    if not w then return 0, nil end

    -- The keys GetItemStats hands back, mapped to what we weight them by
    -- and what to call them on screen.
    local MAP = {
        ITEM_MOD_STRENGTH_SHORT  = { "strength",  "str" },
        ITEM_MOD_AGILITY_SHORT   = { "agility",   "agi" },
        ITEM_MOD_STAMINA_SHORT   = { "stamina",   "sta" },
        ITEM_MOD_INTELLECT_SHORT = { "intellect", "int" },
        ITEM_MOD_SPIRIT_SHORT    = { "spirit",    "spi" },
        RESISTANCE0_NAME         = { "armor",     "armor" },
    }
    local total, parts = 0, {}
    for key, value in pairs(stats) do
        local m = MAP[key]
        if m and type(value) == "number" then
            local weight = w[m[1]]
            if weight and weight ~= 0 then
                total = total + value * weight
                parts[#parts + 1] = ("%s %d"):format(m[2], value)
            end
        end
    end

    -- A weapon's damage swamps its stat line, so it is converted rather
    -- than left out. For a caster the weapon is a stat stick and the rate
    -- is set low to say so.
    local speed, lo, hi = self:WeaponDamage(link)
    if speed and speed > 0 then
        local dps = ((lo + hi) / 2) / speed
        total = total + dps * self:DpsRate()
        table.insert(parts, 1, ("%.1f dps"):format(dps))
    end

    return total, table.concat(parts, ", ")
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
    ns:On("ITEM_DATA_LOAD_RESULT", function(_, id, success)
        if success ~= false then S:OnItemLoaded(id) end
        ns.UI:ItemArrived()
    end)
    ns:On("GET_ITEM_INFO_RECEIVED", function(_, id, success)
        if success ~= false then S:OnItemLoaded(id) end
        ns.UI:ItemArrived()
    end)
    -- Redraw the paperdoll when the character underneath it changes.
    ns.RegisterEvents({ "PLAYER_EQUIPMENT_CHANGED", "UNIT_STATS" })
    local function changed() if ns.Doll and ns.Doll.pane then ns.Doll:Refresh() end end
    ns:On("PLAYER_EQUIPMENT_CHANGED", changed)
    ns:On("UNIT_STATS", function(_, unit) if unit == "player" then changed() end end)
end
