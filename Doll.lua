-- Wick's Gear
-- Doll.lua: the paperdoll you try things on.
--
-- Slots laid out like the character sheet, your own character standing
-- between them, and a stat block that shows what a piece would do to you
-- rather than what it is worth in the abstract.
--
-- The primary stats and armour are exact: the candidate's numbers minus
-- the ones on the piece it would replace. No formulas, no guessing.
--
-- Attack power, crit and health are exact too. The client exposes the
-- conversions the character sheet itself uses, and they take a stat
-- value as an argument, so the honest way to ask what a piece does is to
-- ask for the answer at your stat and again at your stat plus the
-- change. No formulas of ours, nothing to go stale when Forever retunes
-- something, and correct for this class at this level by construction.

local ADDON, ns = ...
local Core = WickCore
local Chrome = Core.Chrome
local C = Chrome.Colors

local Doll = {}
ns.Doll = Doll

local UP   = { 0.35, 0.82, 0.45, 1 }
local DOWN = { 0.85, 0.35, 0.35, 1 }
local ICON = 30

-- Two columns down the sides and the weapons underneath, the way the
-- character sheet reads.
local LEFT  = { 1, 2, 3, 15, 5, 9 }        -- head, neck, shoulder, back, chest, wrist
local RIGHT = { 10, 6, 7, 8, 11, 13 }      -- hands, waist, legs, feet, finger, trinket
local UNDER = { 16, 17, 18 }               -- weapon, off hand, ranged

Doll.trying = {}   -- slot -> { id, link }

local function tint(fs, c) fs:SetTextColor(c[1], c[2], c[3], c[4] or 1) end

-- ============================================================
-- Slots
-- ============================================================

local function makeSlot(parent, slotId)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(ICON, ICON)
    b.slotId = slotId

    b.bg = Chrome:Texture(b, "BACKGROUND", C.shadow)
    b.bg:SetAllPoints()
    Chrome:AddBorder(b)

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 1, -1)
    b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- A fel edge marks a slot holding something you are only trying on.
    b.mark = Chrome:Texture(b, "OVERLAY", C.fel)
    b.mark:SetPoint("BOTTOMLEFT", 1, 1)
    b.mark:SetPoint("BOTTOMRIGHT", -1, 1)
    b.mark:SetHeight(2)
    b.mark:Hide()

    b:RegisterForClicks("AnyUp")
    b:RegisterForDrag("LeftButton")

    b:SetScript("OnEnter", function(s)
        local trying = Doll.trying[s.slotId]
        local link = trying and trying.link or GetInventoryItemLink("player", s.slotId)
        GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
        if link then
            GameTooltip:SetHyperlink(link)
            if trying then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Being tried on. Right-click to put it back.", 0.5, 0.5, 0.5)
            end
        else
            GameTooltip:SetText(ns.Score.SLOT_NAME[s.slotId] or "Slot")
            GameTooltip:AddLine("Empty. Drop something here from the list.", 0.5, 0.5, 0.5, true)
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function(s, button)
        if button == "RightButton" then Doll:Clear(s.slotId) end
    end)
    b:SetScript("OnReceiveDrag", function(s) Doll:DropOnto(s.slotId) end)
    return b
end

-- The paperdoll is built the first time its tab is drawn, but anything
-- can ask to try a piece on before that has happened: right-clicking a
-- row builds nothing by itself. So build on demand, and do nothing at
-- all if there is not yet a pane to build into.
function Doll:Ensure()
    if self.pane then return true end
    local pane = ns.UI and ns.UI.panes and ns.UI.panes.compare
    if not pane then return false end
    self:Build(pane)
    return true
end

function Doll:Refresh()
    if not self.slots then return end
    local S = ns.Score
    for slotId, b in pairs(self.slots) do
        local trying = self.trying[slotId]
        local link = trying and trying.link or GetInventoryItemLink("player", slotId)
        if trying and trying.icon then
            b.icon:SetTexture(trying.icon)
        elseif link then
            b.icon:SetTexture(C_Item.GetItemIconByID(link))
        else
            b.icon:SetTexture(nil)
        end
        b.icon:SetDesaturated(false)
        b.mark:SetShown(trying ~= nil)
    end
    self:RefreshStats()
    self:RefreshModel()
end

-- ============================================================
-- Trying things on
-- ============================================================

function Doll:TryOn(itemID)
    local S = ns.Score
    local info = S:Info(itemID)
    if not info or not info.slot then
        ns.A:Print("that is not something you can wear.")
        return false
    end
    if not S:Usable(info) then
        ns.A:Print("your class cannot use that.")
        return false
    end
    self.trying[info.slot] = { id = itemID, link = S:LinkFor(itemID), icon = info.icon }
    ns.UI:Select("compare")
    if self:Ensure() then self:Refresh() end
    return true
end

function Doll:Clear(slotId)
    if not self.trying[slotId] then return end
    self.trying[slotId] = nil
    self:Refresh()
end

function Doll:ClearAll()
    wipe(self.trying)
    self:Refresh()
end

-- Dragging inside our own window, so the cursor is ours rather than the
-- game's: the list puts an id down and the slot picks it up.
function Doll:DropOnto(slotId)
    local id = ns.UI.dragging
    ns.UI.dragging = nil
    if not id then return end
    local info = ns.Score:Info(id)
    if info and info.slot and info.slot ~= slotId then
        ns.A:Print("that does not go in this slot.")
        return
    end
    self:TryOn(id)
end

-- ============================================================
-- Stats
-- ============================================================

function Doll:Deltas()
    local S = ns.Score
    local out = {}
    for slotId, trying in pairs(self.trying) do
        local new = S:StatsOf(trying.id)
        local old = S:EquippedStats(slotId)
        for _, key in ipairs(S.STAT_ORDER) do
            local d = (new[key] or 0) - (old[key] or 0)
            if d ~= 0 then out[key] = (out[key] or 0) + d end
        end
    end
    return out
end

function Doll:ScoreDelta()
    local S = ns.Score
    local total = 0
    for slotId, trying in pairs(self.trying) do
        total = total + (S:Value(trying.link, trying.id)) - (S:EquippedValue(slotId))
    end
    return total
end

local STAT_INDEX = { str = 1, agi = 2, sta = 3, int = 4, spi = 5 }

local function current(key)
    if key == "armor" then
        local _, effective = UnitArmor("player")
        return effective or 0
    end
    local idx = STAT_INDEX[key]
    if not idx then return 0 end
    local _, effective = UnitStat("player", idx)
    return effective or 0
end

function Doll:RefreshStats()
    local S = ns.Score
    local deltas = self:Deltas()
    local any = next(self.trying) ~= nil

    for i, key in ipairs(S.STAT_ORDER) do
        local row = self.statRows[i]
        local now = current(key)
        local d = deltas[key] or 0
        row.label:SetText(S.STAT_LABEL[key])
        if d == 0 then
            row.value:SetText(tostring(now))
            tint(row.value, C.text)
            row.delta:SetText("")
        else
            row.value:SetText(tostring(now + d))
            tint(row.value, d > 0 and UP or DOWN)
            row.delta:SetText(("%+d"):format(d))
            tint(row.delta, d > 0 and UP or DOWN)
        end
    end

    local sd = self:ScoreDelta()
    if not any then
        self.summary:SetText("Right-click anything in Upgrades or Browse to try it on here.")
        tint(self.summary, C.muted)
    else
        self.summary:SetText(("%+.0f points overall"):format(sd))
        tint(self.summary, sd > 0 and UP or (sd < 0 and DOWN or C.muted))
    end

    self:RefreshDerived(deltas, any)
end

-- ============================================================
-- What those stats turn into
-- ============================================================
-- The character sheet's own conversions, asked for twice: once at your
-- stats and once at your stats plus what the piece would change. The
-- difference is the answer, and it is the client's answer rather than
-- ours.

local function call(fn, ...)
    local f = rawget(_G, fn)
    if type(f) ~= "function" then return nil end
    local ok, v = pcall(f, ...)
    if not ok or type(v) ~= "number" then return nil end
    return v
end

local IDX = { str = 1, agi = 2, sta = 3, int = 4, spi = 5 }

local function healthFrom(sta)
    local per = call("UnitHPPerStamina", "player")
    if not per then return nil end
    -- The first few points of Stamina are worth one health each; only
    -- past the break does the class multiplier apply.
    local brk = rawget(_G, "STAMINA_BREAK") or 20
    return math.min(brk, sta) + math.max(0, sta - brk) * per
end

local function manaFrom(int)
    local per = rawget(_G, "MANA_PER_INTELLECT")
    if type(per) ~= "number" then return nil end
    local brk = rawget(_G, "INTELLECT_BREAK") or 20
    return math.min(brk, int) + math.max(0, int - brk) * per
end

local METRICS = {
    { label = "Attack power", fmt = "%+.0f", calc = function(s)
        local a = call("GetAttackPowerForStat", IDX.str, s.str)
        local b = call("GetAttackPowerForStat", IDX.agi, s.agi)
        if not a and not b then return nil end
        return (a or 0) + (b or 0)
    end },
    { label = "Ranged attack power", fmt = "%+.0f", calc = function(s)
        return call("GetRangedAttackPowerForStat", IDX.agi, s.agi)
    end },
    { label = "Melee crit", fmt = "%+.2f%%", calc = function(s)
        local v = call("GetCritChanceFromStat", IDX.agi, s.agi)
        return v and v * 100 or nil
    end },
    { label = "Spell crit", fmt = "%+.2f%%", calc = function(s)
        local v = call("GetSpellCritChanceFromStat", IDX.int, s.int)
        return v and v * 100 or nil
    end },
    { label = "Health", fmt = "%+.0f", calc = function(s) return healthFrom(s.sta) end },
    { label = "Mana", fmt = "%+.0f", calc = function(s) return manaFrom(s.int) end },
    { label = "Armor from agility", fmt = "%+.0f", calc = function(s)
        local per = rawget(_G, "ARMOR_PER_AGILITY")
        if type(per) ~= "number" then return nil end
        return s.agi * per
    end },
}

function Doll:RefreshDerived(deltas, any)
    if not any then
        self.derived:SetText("")
        return
    end
    local now = {}
    for _, key in ipairs(ns.Score.STAT_ORDER) do now[key] = current(key) end
    local after = {}
    for k, v in pairs(now) do after[k] = v + (deltas[k] or 0) end

    local lines = {}
    for _, m in ipairs(METRICS) do
        local a, b = m.calc(now), m.calc(after)
        if a and b then
            local d = b - a
            -- Anything under a hundredth is rounding, not a change.
            if math.abs(d) >= 0.005 then
                lines[#lines + 1] = ("%s %s"):format(m.label, m.fmt:format(d))
            end
        end
    end

    if #lines == 0 then
        self.derived:SetText("No change to anything the character sheet shows.")
    else
        self.derived:SetText(table.concat(lines, "\n"))
    end
    tint(self.derived, C.muted)
end

-- ============================================================
-- The character
-- ============================================================

function Doll:RefreshModel()
    local m = self.model
    if not m then return end
    local ok = pcall(function()
        m:SetUnit("player")
        m:Undress()
        m:Dress()
        for _, trying in pairs(self.trying) do
            if trying.link then m:TryOn(trying.link) end
        end
    end)
    if not ok then
        -- Some builds refuse a model on a frame this small. The paperdoll
        -- is still useful without a picture, so it just goes away.
        m:Hide()
        self.modelFailed = true
    end
end

-- ============================================================

function Doll:Build(pane)
    self.pane = pane
    self.slots = {}

    local function column(list, anchorPoint, xOff)
        local prev
        for _, slotId in ipairs(list) do
            local b = makeSlot(pane, slotId)
            if prev then b:SetPoint("TOP", prev, "BOTTOM", 0, -6)
            else b:SetPoint(anchorPoint, pane, anchorPoint, xOff, -4) end
            self.slots[slotId] = b
            prev = b
        end
        return prev
    end
    column(LEFT, "TOPLEFT", 4)
    column(RIGHT, "TOPLEFT", 4 + ICON + 128 + 8)

    local prev
    for _, slotId in ipairs(UNDER) do
        local b = makeSlot(pane, slotId)
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 6, 0)
        else b:SetPoint("TOPLEFT", 4 + ICON + 20, -(6 * (ICON + 6)) - 2) end
        self.slots[slotId] = b
        prev = b
    end

    local m = CreateFrame("DressUpModel", nil, pane)
    m:SetPoint("TOPLEFT", 4 + ICON + 8, -4)
    m:SetSize(124, 6 * (ICON + 6) - 8)
    self.model = m

    -- Stats, to the right of the doll.
    local sx = 4 + ICON * 2 + 128 + 20
    self.statRows = {}
    for i = 1, #ns.Score.STAT_ORDER do
        local row = CreateFrame("Frame", nil, pane)
        row:SetSize(170, 16)
        row:SetPoint("TOPLEFT", sx, -4 - (i - 1) * 17)
        row.label = Chrome:Text(row, 11, C.muted)
        row.label:SetPoint("LEFT")
        row.value = Chrome:Text(row, 11)
        row.value:SetPoint("LEFT", 76, 0)
        row.delta = Chrome:Text(row, 11)
        row.delta:SetPoint("LEFT", 124, 0)
        self.statRows[i] = row
    end

    self.summary = Chrome:Text(pane, 12, C.muted)
    self.summary:SetPoint("TOPLEFT", sx, -4 - 6 * 17 - 8)
    self.summary:SetWidth(178)
    self.summary:SetJustifyH("LEFT")

    self.derived = Chrome:Text(pane, 10, C.muted)
    self.derived:SetPoint("TOPLEFT", sx, -4 - 6 * 17 - 34)
    self.derived:SetWidth(178)
    self.derived:SetJustifyH("LEFT")

    local reset = Chrome:Button(pane, "Take it all off", 110, 20)
    reset:SetPoint("BOTTOMLEFT", 4, 4)
    reset:SetScript("OnClick", function() Doll:ClearAll() end)

    self:Refresh()
end
