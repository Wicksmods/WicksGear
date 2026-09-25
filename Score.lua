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
if not WickCore then return end   -- said once in Core.lua
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
-- A method, because every other entry point here is one and calling
-- this with a dot by mistake is silent: the id becomes the table and
-- the client is asked about nothing.
function S:Cached(id) return cached(id) end

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
-- ============================================================
-- Describing an item the client cannot
-- ============================================================
-- On this beta the client only knows an item the character has actually
-- encountered. Asking for a tooltip on any other one gives "Retrieving
-- item information" and keeps giving it, because the data is never
-- coming: there is nothing to wait for. So when the client cannot
-- answer, the tooltip is built from what we shipped instead.
--
-- The client is always asked first. Its answer is the one this server
-- is using, and ours is a printed copy of a website.

local QUALITY_COLOR = {
    poor = { 0.62, 0.62, 0.62 }, common = { 1, 1, 1 },
    uncommon = { 0.12, 1, 0 },   rare = { 0, 0.44, 0.87 },
    epic = { 0.64, 0.21, 0.93 }, legendary = { 1, 0.50, 0 },
}

function S:FillTooltip(tt, id, link)
    if self:Cached(id) and link then
        tt:SetHyperlink(link)
        return true
    end

    local e = ns.ENTRY[id]
    if not e then
        -- Not ours either, so the placeholder is the honest answer.
        tt:SetHyperlink(link or ("item:" .. id))
        return false
    end

    local c = QUALITY_COLOR[e.q or "common"] or QUALITY_COLOR.common
    tt:SetText(e.name ~= "" and e.name or ("Item " .. id), c[1], c[2], c[3])
    if e.slot then tt:AddLine(e.slot, 1, 1, 1) end
    if e.req and e.req > 0 then
        -- Red when you cannot wear it yet, the way the game does it.
        local ok = e.req <= (UnitLevel("player") or 1)
        tt:AddLine("Requires Level " .. e.req, 1, ok and 1 or 0.13, ok and 1 or 0.13)
    end

    local st = e.stats
    if st then
        if st.armor then tt:AddLine(st.armor .. " Armor", 1, 1, 1) end
        for _, key in ipairs(S.STAT_ORDER) do
            if key ~= "armor" and st[key] then
                tt:AddLine(("+%d %s"):format(st[key], S.STAT_LABEL[key]), 0, 1, 0)
            end
        end
    end

    tt:AddLine(" ")
    if e.how == "quest" then
        tt:AddLine(("Quest reward in %s"):format(e.dungeon or "a dungeon")
            .. (e.from and (", from " .. e.from) or ""), 0.31, 0.78, 0.47, true)
    else
        tt:AddLine(("Drops in %s"):format(e.dungeon or "a dungeon")
            .. (e.from and (", from " .. e.from) or ""), 0.31, 0.78, 0.47, true)
    end
    -- The client's own tooltip lists a set and its bonuses; ours did
    -- not, and these are exactly the items it will never draw.
    if e.set then
        local prog = self:SetProgress(e.set)
        tt:AddLine(" ")
        tt:AddLine(prog and ("%s (%d/%d)"):format(e.set, prog.worn, prog.total) or e.set,
            0.83, 0.78, 0.63)
        for _, b in ipairs((prog and prog.bonuses) or {}) do
            local on = prog.worn >= b.pieces
            tt:AddLine(("  %d pieces: %s"):format(b.pieces, b.text),
                on and 0.31 or 0.5, on and 0.78 or 0.5, on and 0.47 or 0.5, true)
        end
        if prog and prog.approximate and #(prog.bonuses or {}) > 0 then
            tt:AddLine("  Bonuses are Classic's; Forever publishes none yet.", 0.5, 0.5, 0.5, true)
        end
        tt:AddLine(" ")
    end
    tt:AddLine("Described from Wick's own data. This character has never seen the item, so the game cannot describe it.", 0.5, 0.5, 0.5, true)
    self:AddComparison(tt, id)
    return false
end

-- The game compares an item against what you are wearing when you hold
-- shift. It cannot do that for an item it has never heard of, and those
-- are exactly the ones this list is full of, so the comparison is drawn
-- here instead. It is also the more useful direction: the difference,
-- rather than two tooltips to read against each other.
function S:AddComparison(tt, id)
    local e = ns.ENTRY[id]
    local info = self:Info(id)
    local slot = info and info.slot
    if not e or not slot then return end
    local worn = self:EquippedStats(slot)
    local new = e.stats or {}
    local bits = {}
    for _, key in ipairs(S.STAT_ORDER) do
        local d = (new[key] or 0) - (worn[key] or 0)
        if d ~= 0 then
            bits[#bits + 1] = { key = key, d = d }
        end
    end
    tt:AddLine(" ")
    if #bits == 0 then
        tt:AddLine("No change from what you are wearing.", 0.5, 0.5, 0.5)
        return
    end
    tt:AddLine("Against what you are wearing", 0.83, 0.78, 0.63)
    for _, b in ipairs(bits) do
        local up = b.d > 0
        tt:AddLine(("%+d %s"):format(b.d, S.STAT_LABEL[b.key]),
            up and 0.31 or 0.90, up and 0.78 or 0.30, up and 0.47 or 0.30)
    end
end

-- A link you can put in chat.
--
-- The client can only build one for an item it has met, and on this beta
-- that is a minority of the list, so the rest have to be hand built.
--
-- The first attempt wrote "|Hitem:279899|h[Name]|h", which carries
-- everything a receiving client needs and still would not go in the chat
-- box: an item link is a fixed shape on any given build and a one field
-- one is not it. Rather than guess how many fields this build wants, ask
-- it. The player is wearing items, every one of those gives a real link,
-- and counting its fields gives the shape to match.
local linkFields   -- learned, not assumed

local function learnShape(link)
    if type(link) ~= "string" then return end
    local payload = link:match("|Hitem:([^|]*)|h")
    if not payload then return end
    local n = 1
    for _ in payload:gmatch(":") do n = n + 1 end
    if n > 1 then linkFields = n end
end

-- Read off what the player is wearing. Runs at login and again whenever a
-- real link passes through, so a build that changes its mind is followed
-- rather than argued with.
function S:LearnLinkShape()
    if linkFields then return linkFields end
    for slot = 1, 19 do
        local ok, link = pcall(GetInventoryItemLink, "player", slot)
        if ok and link then
            learnShape(link)
            if linkFields then break end
        end
    end
    return linkFields
end

function S:LinkFields() return linkFields end

function S:ChatLink(id)
    local ok, _, link = pcall(C_Item.GetItemInfo, id)
    if ok and link then
        learnShape(link)
        return link, "client"
    end

    -- Not met yet. Ask for it, so the next shift-click on this row gets
    -- the client's own link rather than ours.
    pcall(C_Item.RequestLoadItemDataByID, id)

    local e = ns.ENTRY[id]
    if not e or not e.name or e.name == "" then return nil end
    local c = QUALITY_COLOR[e.q or "common"] or QUALITY_COLOR.common
    -- %x wants whole numbers; the palette is fractions.
    local hex = ("%02x%02x%02x"):format(
        math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
    local fields = linkFields or self:LearnLinkShape() or 15
    local payload = tostring(id) .. string.rep(":", fields - 1)
    return ("|cff%s|Hitem:%s|h[%s]|h|r"):format(hex, payload, e.name), "built"
end

S.STAT_ORDER = { "str", "agi", "sta", "int", "spi", "armor" }
S.STAT_LABEL = { str = "Strength", agi = "Agility", sta = "Stamina",
                 int = "Intellect", spi = "Spirit", armor = "Armor" }
-- Short forms, for a list row where the whole line has to fit.
S.STAT_SHORT = { str = "Str", agi = "Agi", sta = "Sta",
                 int = "Int", spi = "Spi", armor = "Armor" }

-- What a piece gives, on one line. Armour last, because it is the one
-- that is a flat number rather than a plus.
function S:StatLine(id)
    local st = self:StatsOf(id)
    if not st then return "" end
    local parts = {}
    for _, key in ipairs(S.STAT_ORDER) do
        local v = st[key]
        if v and v ~= 0 and key ~= "armor" then
            parts[#parts + 1] = ("+%d %s"):format(v, S.STAT_SHORT[key] or key)
        end
    end
    if st.armor and st.armor ~= 0 then
        parts[#parts + 1] = ("%d Armor"):format(st.armor)
    end
    return table.concat(parts, "  ")
end

-- The colour the game would print the name in. The client knows once it
-- has met the item; our own data carries the quality as a word for the
-- ones it has not.
local QUALITY_RGB = {
    [0] = { 0.62, 0.62, 0.62 }, [1] = { 1, 1, 1 }, [2] = { 0.12, 1, 0 },
    [3] = { 0, 0.44, 0.87 }, [4] = { 0.64, 0.21, 0.93 }, [5] = { 1, 0.50, 0 },
}
local QUALITY_WORD = {
    poor = 0, common = 1, uncommon = 2, rare = 3, epic = 4, legendary = 5,
}

function S:QualityRGB(id)
    local info = self:Info(id)
    local q = info and info.quality
    if type(q) ~= "number" then
        local e = ns.ENTRY[id]
        q = e and QUALITY_WORD[e.q or ""]
    end
    return QUALITY_RGB[q] or QUALITY_RGB[1]
end

-- What the client says a set gives.
--
-- The item tooltip lists the bonuses, which means the client holds
-- Forever's own set data. That beats the scraped Classic text, which is
-- a guess about this build, so the client is asked first and the scrape
-- is only a fallback for a set nothing here can answer for.
--
-- Cached per set: reading a tooltip is cheap but not free, and the
-- answer cannot change inside a session.
local clientBonus = {}

-- Both wordings, because the phrasing has moved across expansions.
local function bonusFrom(text)
    local n, effect = text:match("^%((%d+)%)%s*Set%s*:%s*(.+)$")
    if not n then n, effect = text:match("^(%d+)%s+pieces?:%s*(.+)$") end
    if n and effect and effect ~= "" then
        return tonumber(n), (effect:gsub("%s+$", ""))
    end
end

function S:ClientSetBonuses(setName)
    if clientBonus[setName] ~= nil then
        return clientBonus[setName] or nil
    end
    -- Any item of the set the client can describe will carry the whole
    -- list, so the first one that answers is enough.
    for id, e in pairs(ns.ENTRY or {}) do
        if e.set == setName then
            local link = self:LinkFor(id)
            local d = link and C_TooltipInfo and C_TooltipInfo.GetHyperlink
                and C_TooltipInfo.GetHyperlink(link)
            if d and d.lines then
                local rows = {}
                for _, line in ipairs(d.lines) do
                    local pieces, effect = bonusFrom((line.leftText or ""):gsub("^%s+", ""))
                    if pieces then rows[#rows + 1] = { pieces = pieces, text = effect } end
                end
                if #rows > 0 then
                    table.sort(rows, function(a, b) return a.pieces < b.pieces end)
                    clientBonus[setName] = rows
                    return rows
                end
            end
        end
    end
    -- A miss is remembered so the sets tab does not rescan every entry
    -- for every group on every draw, but it is not remembered forever:
    -- the client answers about an item only once it has the data, and
    -- that arrives after the first draw. ForgetSetCache is called when
    -- it does, or a set the client could not describe yet would fall
    -- back to Classic's numbers for the rest of the session.
    clientBonus[setName] = false
    return nil
end

function S:ForgetSetCache()
    clientBonus = {}
    -- Which sets this class can wear is an item-data question too.
    self.wearableSets = nil
end

-- ============================================================
-- Sets
-- ============================================================
-- Every set the data knows, and the pieces in it. Walked once: the
-- tables do not change after load, and doing it per keystroke in Browse
-- was work for nothing.
local setsCache, setOrderCache
function S:SetGroups()
    if setsCache then return setOrderCache, setsCache end
    local groups = {}
    local function sweep(tbl)
        for _, rows in pairs(tbl or {}) do
            for _, e in ipairs(rows) do
                if e.set then
                    groups[e.set] = groups[e.set] or {}
                    table.insert(groups[e.set], e)
                end
            end
        end
    end
    -- The dungeon table nests its rows one level deeper than the others.
    local flat = {}
    for name, d in pairs(ns.DUNGEONS or {}) do flat[name] = d.items end
    sweep(flat)
    sweep(ns.CRAFTED)
    sweep(ns.QUESTS)
    local order = {}
    for name in pairs(groups) do order[#order + 1] = name end
    table.sort(order)
    setsCache, setOrderCache = groups, order
    return order, groups
end

-- The sets this character could actually wear, which is the list worth
-- stepping through in the wardrobe: a plate set is not a thing a rogue
-- wants to page past.
function S:WearableSets()
    if self.wearableSets then return self.wearableSets end
    local order, groups = self:SetGroups()
    local out = {}
    for _, name in ipairs(order) do
        for _, e in ipairs(groups[name]) do
            local info = self:Info(e.id)
            if info and info.slot and self:Usable(info) then
                out[#out + 1] = name
                break
            end
        end
    end
    -- Nothing usable yet means the client has not described anything
    -- yet, not that the character can wear nothing. Do not cache that.
    if #out == 0 then return order end
    self.wearableSets = out
    return out
end

-- How much of a set is actually on the character, and what that has
-- earned.
--
-- The count is read off the equipped slots, so it is right for this
-- build whatever Wowhead thinks. The bonus text is Classic's, because
-- Forever publishes none, which is why the caller is told so rather
-- than left to assume.
-- What you have on, slot to item id. The one place that asks the
-- client, so the preview can hand over a changed copy instead.
function S:EquippedIDs()
    local out = {}
    if not GetInventoryItemID then return out end
    for slot = 1, 19 do
        local ok, id = pcall(GetInventoryItemID, "player", slot)
        if ok and id then out[slot] = id end
    end
    return out
end

-- `worn` takes a slot-to-id map, which is what lets the compare column
-- count the pieces you are trying on. Two pieces of a set in the
-- preview and no two-piece bonus shown is the column failing at the one
-- job it has. Nothing passed means the gear you actually have on.
function S:SetProgress(setName, wearing)
    if not setName then return nil end
    wearing = wearing or self:EquippedIDs()
    local has = {}
    for _, id in pairs(wearing) do has[id] = true end

    local worn, total = 0, 0
    -- Which ids belong to this set, from whichever source carries them.
    for id, e in pairs(ns.ENTRY or {}) do
        if e.set == setName then
            total = total + 1
            if has[id] then worn = worn + 1 end
        end
    end
    if total == 0 then return nil end

    -- The client first: it is this build. The scrape is Classic's guess
    -- at it and only stands in when the client will not say.
    local fromClient = self:ClientSetBonuses(setName)
    local list = fromClient or (ns.SET_BONUS or {})[setName] or {}

    local earned, next_ = {}, nil
    for _, b in ipairs(list) do
        if worn >= b.pieces then
            earned[#earned + 1] = b
        elseif not next_ or b.pieces < next_.pieces then
            next_ = b
        end
    end
    return { worn = worn, total = total, earned = earned, next = next_,
             bonuses = list, fromClient = fromClient ~= nil,
             -- Only a fallback needs the warning. What the client said
             -- about its own sets is not approximate.
             approximate = fromClient == nil and ns.SET_BONUS_APPROXIMATE == true }
end

-- Every set bonus the gear on your back has actually earned, as flat
-- rows ready to print. Only the earned ones: what a set would give at
-- four pieces when you have two is a tooltip's business, not a readout
-- of what you have.
function S:EquippedSetBonuses(wearing)
    wearing = wearing or self:EquippedIDs()
    local seen, out = {}, {}
    for _, id in pairs(wearing) do
        local e = ns.ENTRY[id]
        local set = e and e.set
        if set and not seen[set] then
            seen[set] = true
            local prog = self:SetProgress(set, wearing)
            for _, b in ipairs((prog and prog.earned) or {}) do
                out[#out + 1] = { set = set, worn = prog.worn, total = prog.total,
                                  pieces = b.pieces, text = b.text }
            end
        end
    end
    return out
end

-- Whether this exact item is in one of the equipped slots.
function S:IsEquipped(id)
    if not GetInventoryItemID then return false end
    for slot = 1, 19 do
        local ok, worn = pcall(GetInventoryItemID, "player", slot)
        if ok and worn == id then return true end
    end
    return false
end

-- Whether the weapon actually on the character is a two-hander, which
-- decides whether putting something in the off hand takes it off.
function S:EquippedIsTwoHand()
    if not GetInventoryItemID then return false end
    local ok, id = pcall(GetInventoryItemID, "player", 16)
    if not ok or not id then return false end
    local info = self:Info(id)
    return info ~= nil and info.equipLoc == "INVTYPE_2HWEAPON"
end

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
    -- Learn what an item link looks like on this build before anything
    -- needs to make one.
    ns.RegisterEvents({ "GET_ITEM_INFO_RECEIVED", "PLAYER_ENTERING_WORLD" })
    ns:On("PLAYER_ENTERING_WORLD", function() S:LearnLinkShape() end)
    ns:On("ITEM_DATA_LOAD_RESULT", function() ns.UI:ItemArrived() end)
    ns:On("GET_ITEM_INFO_RECEIVED", function() ns.UI:ItemArrived() end)
    -- Redraw the paperdoll when the character underneath it changes.
    ns.RegisterEvents({ "PLAYER_EQUIPMENT_CHANGED", "UNIT_STATS" })
    local function changed() if ns.Doll and ns.Doll.pane then ns.Doll:Refresh() end end
    ns:On("PLAYER_EQUIPMENT_CHANGED", changed)
    ns:On("UNIT_STATS", function(_, unit) if unit == "player" then changed() end end)
end
