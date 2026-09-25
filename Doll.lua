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
if not WickCore then return end   -- said once in Core.lua
local Core = WickCore
local Chrome = Core.Chrome
local C = Chrome.Colors

local Doll = {}
ns.Doll = Doll

local UP   = { 0.35, 0.82, 0.45, 1 }
local DOWN = { 0.85, 0.35, 0.35, 1 }
-- The column is the wardrobe, so the picture of the character is the
-- thing worth the width. The slots are indicators under it: small
-- enough to leave the model alone, big enough to drop a piece onto.
local SLOT = 20
local PICK_H = 22
local MODEL_H = 280
local STAT_H = 16
local DERIVED_ROWS = 8


Doll.trying = {}   -- slot -> { id, link } or { empty = true }

-- An entry of { empty = true } means this slot is deliberately bare in
-- the comparison, which is different from not trying anything in it.
local MAIN_HAND, OFF_HAND = 16, 17

local function tint(fs, c) fs:SetTextColor(c[1], c[2], c[3], c[4] or 1) end

-- ============================================================
-- Slots
-- ============================================================

local function makeSlot(parent, slotId, size)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size or SLOT, size or SLOT)
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
            -- What you are wearing is always cached, so that one can go
            -- straight to the game. A piece being tried on may be one
            -- this character has never met, which the game cannot
            -- describe, so it goes through our own describer.
            if trying then
                ns.Score:FillTooltip(GameTooltip, trying.id, link)
            else
                GameTooltip:SetHyperlink(link)
            end
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

function Doll:TryOn(itemID, quiet)
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
    -- Picked by hand, so the set name over the model is no longer what
    -- the character is wearing. WearSet puts its own back afterwards.
    self.setOn = nil

    -- A two-hander takes the off hand with it. Without this the compare
    -- counted a two-hander and a shield at once, which is not something
    -- you can wear, and every number came out too high.
    if info.equipLoc == "INVTYPE_2HWEAPON" then
        self.trying[OFF_HAND] = { empty = true }
    elseif info.slot == OFF_HAND then
        -- And the other way: putting something in the off hand while a
        -- two-hander is in the weapon slot takes the two-hander off.
        local main = self.trying[MAIN_HAND]
        local mainLoc = main and main.id and S:Info(main.id) and S:Info(main.id).equipLoc
        if mainLoc == "INVTYPE_2HWEAPON" then
            self.trying[MAIN_HAND] = { empty = true }
        elseif not main and S:EquippedIsTwoHand() then
            self.trying[MAIN_HAND] = { empty = true }
        end
    end

    -- The caller may be putting a whole set on and will say when it is
    -- done, rather than redrawing the window once per piece.
    if not quiet then self:Changed() end
    return true
end

-- The preview changed, so both halves of the window are stale: the doll
-- and the stats here, and the highlights in the list beside it. TryOn
-- redrew both and the two clears redrew only the doll, so taking
-- everything off left every row in the list still lit.
function Doll:Changed()
    if ns.UI and ns.UI.Refresh then ns.UI:Refresh() end
    if self:Ensure() then self:Refresh() end
end

function Doll:Clear(slotId)
    if not self.trying[slotId] then return end
    self.trying[slotId] = nil
    self:Changed()
end

-- Take a previewed piece off, wherever it went on. A two-hander
-- emptied the off hand when it went on, so taking it off gives the off
-- hand back rather than leaving a slot pretending to be bare.
function Doll:Untry(id)
    if not id then return false end
    local found
    for slotId, t in pairs(self.trying) do
        if t.id == id then found = slotId break end
    end
    if not found then return false end
    self.trying[found] = nil
    if found == MAIN_HAND then
        local off = self.trying[OFF_HAND]
        if off and off.empty then self.trying[OFF_HAND] = nil end
    end
    self:Changed()
    return true
end

-- Whether this item is one of the pieces currently on the doll.
function Doll:IsTrying(id)
    if not id then return false end
    for _, t in pairs(self.trying) do
        if t.id == id then return true end
    end
    return false
end

function Doll:ClearAll()
    wipe(self.trying)
    self.setOn = nil
    self:Changed()
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
        local new = trying.empty and {} or S:StatsOf(trying.id)
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
        local gain = trying.empty and 0 or S:Value(trying.link, trying.id)
        total = total + gain - (S:EquippedValue(slotId))
    end
    return total
end

local STAT_INDEX = { str = 1, agi = 2, sta = 3, int = 4, spi = 5 }

-- The client hands some of these back as secret numbers. A secret can be
-- shown but not added to, and the arithmetic throws in our name, so every
-- value read off the unit has to be treated as possibly untouchable.
-- There is no predicate for a plain stat the way there is for power, so
-- the only honest test is to try the addition and see.
local function plain(v)
    local R = WickCore and WickCore.Restrict
    if R and R.IsSecret and R:IsSecret(v) then return nil end
    if type(v) ~= "number" then return nil end
    -- Belt and braces: if the client has no issecretvalue, the only
    -- test left is the addition itself.
    local ok = pcall(function() return v + 0 end)
    if not ok then return nil end
    return v
end

-- Rendering a secret is allowed; turning one into a string is not
-- guaranteed to be. Fall back to a dash rather than an error.
local function show(v)
    local ok, str = pcall(function() return tostring(v) end)
    if ok and type(str) == "string" and not str:find("table") then return str end
    return "?"
end

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

-- The bonus block as rows, which is what gets drawn and what the
-- checks read: a set line, then one line per bonus of that set.
function Doll:BonusRows()
    local S = ns.Score
    local wearing = self:Wearing()
    local nowSets = {}
    for _, got in ipairs(S:EquippedSetBonuses()) do
        nowSets[got.set .. "/" .. got.pieces] = true
    end

    local order, bySet = {}, {}
    for _, got in ipairs(S:EquippedSetBonuses(wearing)) do
        if not bySet[got.set] then
            bySet[got.set] = {}
            order[#order + 1] = got.set
        end
        local group = bySet[got.set]
        group[#group + 1] = got
        group.total, group.worn = got.total, got.worn
    end

    local rows = {}
    for _, set in ipairs(order) do
        local group = bySet[set]
        table.sort(group, function(a, b) return a.pieces < b.pieces end)
        rows[#rows + 1] = { kind = "set", set = set,
                            worn = group.worn, total = group.total }
        for _, got in ipairs(group) do
            -- Green for one the preview would earn you, the way the
            -- stat deltas are green.
            rows[#rows + 1] = { kind = "bonus", set = set,
                                pieces = got.pieces, total = got.total,
                                text = got.text,
                                have = nowSets[set .. "/" .. got.pieces] == true }
        end
    end
    return rows
end

-- What you would have on if you kept the preview: whatever is being
-- tried on, and the equipped gear everywhere else. An emptied slot, the
-- off hand a two-hander takes with it, is empty here too.
function Doll:Wearing()
    local out = ns.Score:EquippedIDs()
    for slotId, trying in pairs(self.trying) do
        out[slotId] = (not trying.empty) and trying.id or nil
    end
    return out
end

-- Lay the bonus rows out. The count sits in a narrow lane and the
-- sentence wraps inside the rest, so a second line lands under the
-- first line of the sentence rather than under the count.
local NUM_W = 34

function Doll:DrawBonuses()
    local inner = self.setInner
    if not inner then return end
    local rows = self:BonusRows()
    local width = tonumber(inner:GetWidth()) or 300
    local y = 0
    for i, row in ipairs(rows) do
        local r = self.setRows[i]
        if not r then
            r = CreateFrame("Frame", nil, inner)
            r.num = Chrome:Text(r, 10, C.muted)
            r.num:SetPoint("TOPLEFT", 2, 0)
            r.num:SetWidth(NUM_W)
            r.num:SetJustifyH("RIGHT")
            r.text = Chrome:Text(r, 10, C.text)
            r.text:SetPoint("TOPLEFT", NUM_W + 8, 0)
            r.text:SetJustifyH("LEFT")
            self.setRows[i] = r
        end
        r:SetWidth(width)
        r.text:SetWidth(math.max(40, width - NUM_W - 10))

        if row.kind == "set" then
            r.num:SetText("")
            r.text:SetText(("%s  |cff8a8270%d/%d worn|r")
                :format(row.set, row.worn, row.total))
            tint(r.text, C.text)
        else
            r.num:SetText(("%d/%d"):format(row.pieces, row.total))
            tint(r.num, row.have and C.muted or C.fel)
            r.text:SetText(row.text)
            tint(r.text, row.have and C.muted or C.fel)
        end

        local h = math.max(12, math.ceil(tonumber(r.text.GetStringHeight
            and r.text:GetStringHeight()) or 12))
        r:SetHeight(h)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 0, -y)
        r:Show()
        y = y + h + 2
    end
    for i = #rows + 1, #self.setRows do self.setRows[i]:Hide() end
    inner:SetHeight(math.max(1, y))
end

function Doll:RefreshStats()
    local S = ns.Score
    local deltas = self:Deltas()
    local any = next(self.trying) ~= nil

    for i, key in ipairs(S.STAT_ORDER) do
        local row = self.statRows[i]
        local raw = current(key)
        local now = plain(raw)
        local d = deltas[key] or 0
        -- Short forms: a lane is half a column wide now.
        row.label:SetText(S.STAT_SHORT[key] or S.STAT_LABEL[key])
        if d == 0 then
            row.value:SetText(show(raw))
            tint(row.value, C.text)
            row.delta:SetText("")
        else
            -- With a plain number we can show what it would become. With
            -- a secret we can only show the change, which is ours anyway.
            row.value:SetText(now and tostring(now + d) or show(raw))
            tint(row.value, C.text)
            row.delta:SetText(("%+d"):format(d))
            tint(row.delta, d > 0 and UP or DOWN)
        end
    end

    self:DrawDerived()

    -- What the gear you have on is actually giving you.
    self:DrawBonuses()

    local sd = self:ScoreDelta()
    if not any then
        self.summary:SetText("Page through a set above, or right-click anything in the list.")
        tint(self.summary, C.muted)
    else
        self.summary:SetText(("%+.0f points overall"):format(sd))
        tint(self.summary, sd > 0 and UP or (sd < 0 and DOWN or C.muted))
    end

    self:RefreshPicker()
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

-- delta is set when the number coming in is a change rather than a
-- total, which happens when the client will not let us read the total.
-- Past the break the curve is a straight line, so the change alone is
-- enough.
local function healthFrom(sta, delta)
    local per = call("UnitHPPerStamina", "player")
    if not per then return nil end
    if delta then return sta * per end
    -- The first few points of Stamina are worth one health each; only
    -- past the break does the class multiplier apply.
    local brk = rawget(_G, "STAMINA_BREAK") or 20
    return math.min(brk, sta) + math.max(0, sta - brk) * per
end

local function manaFrom(int, delta)
    local per = rawget(_G, "MANA_PER_INTELLECT")
    if type(per) ~= "number" then return nil end
    if delta then return int * per end
    local brk = rawget(_G, "INTELLECT_BREAK") or 20
    return math.min(brk, int) + math.max(0, int - brk) * per
end

-- Several of these come back as secret numbers, and a secret is not a
-- number: it can be shown but not added to. plain sends those back as
-- nothing, which is how a row ends up reading as a dash rather than
-- throwing in our name.
local function unitTotal(fn, ...)
    local f = rawget(_G, fn)
    if type(f) ~= "function" then return nil end
    local ok, a, b, c = pcall(f, ...)
    if not ok then return nil end
    a = plain(a)
    if not a then return nil end
    return a + (plain(b) or 0) + (plain(c) or 0)
end

-- label is the long form, short is what fits a lane; cur formats the
-- total and fmt formats the change.
local METRICS = {
    { label = "Attack power", short = "AP", cur = "%.0f", fmt = "%+.0f",
      now = function() return unitTotal("UnitAttackPower", "player") end,
      calc = function(s)
        local a = call("GetAttackPowerForStat", IDX.str, s.str)
        local b = call("GetAttackPowerForStat", IDX.agi, s.agi)
        if not a and not b then return nil end
        return (a or 0) + (b or 0)
    end },
    { label = "Ranged attack power", short = "Ranged AP", cur = "%.0f", fmt = "%+.0f",
      now = function() return unitTotal("UnitRangedAttackPower", "player") end,
      calc = function(s)
        return call("GetRangedAttackPowerForStat", IDX.agi, s.agi)
    end },
    { label = "Melee crit", short = "Crit", cur = "%.1f%%", fmt = "%+.2f%%",
      now = function() return call("GetCritChance") end,
      calc = function(s)
        local v = call("GetCritChanceFromStat", IDX.agi, s.agi)
        return v and v * 100 or nil
    end },
    { label = "Spell crit", short = "Spell crit", cur = "%.1f%%", fmt = "%+.2f%%",
      now = function() return call("GetSpellCritChance", 2) end,
      calc = function(s)
        local v = call("GetSpellCritChanceFromStat", IDX.int, s.int)
        return v and v * 100 or nil
    end },
    { label = "Health", short = "Health", cur = "%.0f", fmt = "%+.0f",
      now = function() return unitTotal("UnitHealthMax", "player") end,
      calc = function(s, delta) return healthFrom(s.sta, delta) end },
    { label = "Mana", short = "Mana", cur = "%.0f", fmt = "%+.0f",
      now = function() return unitTotal("UnitPowerMax", "player", 0) end,
      calc = function(s, delta) return manaFrom(s.int, delta) end },
    { label = "Armor from agility", short = "Armor/agi", cur = "%.0f", fmt = "%+.0f",
      calc = function(s)
        local per = rawget(_G, "ARMOR_PER_AGILITY")
        if type(per) ~= "number" then return nil end
        return s.agi * per
    end },
}

-- What the client says these are now, and what our change would do to
-- them. The total is the client's own reading rather than a conversion
-- of ours run at the current stats: health from stamina is not your
-- health, and printing it under the word Health would be a number that
-- disagrees with the character sheet.
function Doll:DerivedRows()
    local deltas = self:Deltas()
    local any = next(self.trying) ~= nil

    -- Two ways to the same change. If the client lets us read our own
    -- stats as plain numbers, ask its conversions what they are worth
    -- now and what they would be worth after, and subtract: that
    -- respects the breakpoints exactly. If the stats come back secret we
    -- cannot do that, so feed the conversions the change on its own.
    -- Every one of them is linear above the first twenty points, which
    -- any character past the starting zone is well clear of.
    local now, exact = {}, true
    for _, key in ipairs(ns.Score.STAT_ORDER) do
        local v = plain(current(key))
        if not v then
            exact = false
            break
        end
        now[key] = v
    end

    local rows = {}
    for _, m in ipairs(METRICS) do
        local d
        if any then
            if exact then
                local after = {}
                for k, v in pairs(now) do after[k] = v + (deltas[k] or 0) end
                local a, b = m.calc(now), m.calc(after)
                if a and b then d = b - a end
            else
                d = m.calc(setmetatable({}, { __index = function(_, k)
                    return deltas[k] or 0
                end }), true)
            end
        end
        -- Anything under a hundredth is rounding, not a change.
        if d and math.abs(d) < 0.005 then d = nil end

        local total = m.now and m.now() or nil
        if total or d then
            rows[#rows + 1] = {
                label = m.label,
                short = m.short,
                -- A dash where the client will not say. Any of these can
                -- come back secret.
                value = total and m.cur:format(total) or "-",
                delta = d and m.fmt:format(d) or "",
                change = d,
            }
        end
    end
    return rows
end

function Doll:DrawDerived()
    local rows = self:DerivedRows()
    for i, row in ipairs(self.derivedRows) do
        local r = rows[i]
        if r then
            row.label:SetText(r.short)
            row.value:SetText(r.value)
            tint(row.value, C.text)
            row.delta:SetText(r.delta)
            if r.change then
                tint(row.delta, r.change > 0 and UP or DOWN)
            end
            row:Show()
        else
            row:Hide()
        end
    end
end

-- ============================================================
-- The character
-- ============================================================

-- Which way the character is turned. Kept here rather than on the
-- model because the model is told again after every redress.
Doll.facing = 0

function Doll:Face(facing)
    self.facing = facing
    local m = self.model
    if m and m.SetFacing then pcall(m.SetFacing, m, facing) end
end

function Doll:RefreshModel()
    local m = self.model
    if not m then return end
    local ok = pcall(function()
        m:SetUnit("player")
        -- Four per cent closer, which is the character four per cent
        -- bigger without taking width from the slots either side of it.
        -- The frame is already as wide as the column allows.
        if m.SetCamDistanceScale then m:SetCamDistanceScale(1 / 1.04) end
        m:Undress()
        m:Dress()
        for slotId, trying in pairs(self.trying) do
            if trying.link then
                m:TryOn(trying.link)
            elseif trying.empty and m.UndressSlot then
                m:UndressSlot(slotId)
            end
        end
        -- SetUnit puts the character back to front-on, and this runs
        -- every time you try a piece on, so a model you had turned
        -- would snap round on every click of the list.
        if m.SetFacing then m:SetFacing(self.facing or 0) end
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

    -- Picker, character, slots, readings, bonuses: one column, top to
    -- bottom. The model gets the whole width, because the picture of the
    -- set is what the column is for.
    local W = tonumber(pane:GetWidth()) or 324
    local sw = W - 8

    local pick = CreateFrame("Frame", nil, pane)
    pick:SetPoint("TOPLEFT", 4, -2)
    pick:SetSize(sw, PICK_H)
    local back = Chrome:Button(pick, "<", 22, 18)
    back:SetPoint("LEFT")
    local fwd = Chrome:Button(pick, ">", 22, 18)
    fwd:SetPoint("RIGHT")
    back:SetScript("OnClick", function() Doll:StepSet(-1) end)
    fwd:SetScript("OnClick", function() Doll:StepSet(1) end)
    self.setLabel = Chrome:Text(pick, 11, C.fel)
    self.setLabel:SetPoint("LEFT", back, "RIGHT", 6, 0)
    self.setLabel:SetPoint("RIGHT", fwd, "LEFT", -6, 0)
    self.setLabel:SetJustifyH("CENTER")
    self.setPick = pick

    local m = CreateFrame("DressUpModel", nil, pane)
    m:SetPoint("TOPLEFT", 4, -(PICK_H + 4))
    m:SetSize(sw, MODEL_H)
    self.model = m

    -- Drag to turn the character. A set is a thing you look at from
    -- behind as well as the front, and the shoulders are most of what
    -- the front view hides.
    m:EnableMouse(true)
    m:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then
            Doll.turnFrom = GetCursorPosition()
        elseif button == "RightButton" then
            -- Back to front-on, for a model spun somewhere useless.
            -- Right-click rather than double-click: a model widget does
            -- not inherit the click handlers a frame has, and asking it
            -- for OnDoubleClick raises.
            Doll:Face(0)
        end
    end)
    m:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then Doll.turnFrom = nil end
    end)
    m:SetScript("OnUpdate", function()
        if not Doll.turnFrom then return end
        local x = GetCursorPosition()
        Doll:Face(Doll.facing + (x - Doll.turnFrom) * 0.01)
        Doll.turnFrom = x
    end)

    -- One strip rather than two columns: what you have on, what you are
    -- trying, and somewhere to drop a piece from the list.
    local stripY = -(PICK_H + 4 + MODEL_H + 8)
    local STRIP = ns.Score.SLOT_ORDER
    local stripW = #STRIP * SLOT + (#STRIP - 1)
    local sx = math.max(4, math.floor((W - stripW) / 2))
    local prev
    for _, slotId in ipairs(STRIP) do
        local b = makeSlot(pane, slotId, SLOT)
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 1, 0)
        else b:SetPoint("TOPLEFT", sx, stripY) end
        self.slots[slotId] = b
        prev = b
    end

    -- Two lanes of readings. A row is label, total, change, and the
    -- lanes are measured off the column so they hold at any width.
    local colW = math.floor(sw / 2)
    local sy = stripY - SLOT - 10
    local function readout(i, x)
        local row = CreateFrame("Frame", nil, pane)
        row:SetSize(colW - 4, STAT_H - 1)
        row:SetPoint("TOPLEFT", x, sy - (i - 1) * STAT_H)
        row.label = Chrome:Text(row, 10, C.muted)
        row.label:SetPoint("LEFT")
        row.value = Chrome:Text(row, 10)
        row.value:SetPoint("LEFT", math.floor(colW * 0.40), 0)
        row.delta = Chrome:Text(row, 10)
        row.delta:SetPoint("LEFT", math.floor(colW * 0.72), 0)
        return row
    end
    self.statRows = {}
    for i = 1, #ns.Score.STAT_ORDER do self.statRows[i] = readout(i, 4) end
    self.derivedRows = {}
    for i = 1, DERIVED_ROWS do
        local row = readout(i, 4 + colW)
        row:Hide()
        self.derivedRows[i] = row
    end

    local fy = sy - math.max(#ns.Score.STAT_ORDER, DERIVED_ROWS) * STAT_H - 6
    self.summary = Chrome:Text(pane, 11, C.muted)
    self.summary:SetPoint("TOPLEFT", 4, fy)
    self.summary:SetWidth(sw)
    self.summary:SetJustifyH("LEFT")

    -- Earned set bonuses, under the readings. Only what you have
    -- actually got: an unearned bonus is not information about your
    -- character, and the tooltip carries the full list. It takes
    -- whatever is left at the bottom of the column and scrolls inside
    -- it, since it is as long as the gear makes it.
    local setScroll = CreateFrame("ScrollFrame", nil, pane)
    setScroll:SetPoint("TOPLEFT", 4, fy - 30)
    setScroll:SetPoint("RIGHT", pane, "RIGHT", -4, 0)
    setScroll:SetPoint("BOTTOM", pane, "BOTTOM", 0, 4)
    setScroll:EnableMouseWheel(true)
    setScroll:SetScript("OnMouseWheel", function(f, delta)
        local inner = f:GetScrollChild()
        local range = math.max(0, (tonumber(inner and inner:GetHeight()) or 0)
            - (tonumber(f:GetHeight()) or 0))
        if range <= 0 then return end
        f:SetVerticalScroll(math.min(range,
            math.max(0, (tonumber(f:GetVerticalScroll()) or 0) - delta * 20)))
    end)
    local setInner = CreateFrame("Frame", nil, setScroll)
    setInner:SetSize(sw, 1)
    setScroll:SetScrollChild(setInner)
    setScroll:SetScript("OnSizeChanged", function(f)
        setInner:SetWidth(f:GetWidth() or sw)
    end)
    self.setScroll = setScroll

    -- A row per line: the count in a lane of its own, the sentence in
    -- the rest. One font string for both meant a wrapped sentence went
    -- back to the left margin and ran under the count.
    self.setInner = setInner
    self.setRows = {}

    -- By the heading rather than under a page of readings.
    local reset = Chrome:Button(pane, "Take it all off", 104, 18)
    reset:SetPoint("TOPRIGHT", pane, "TOPRIGHT", -2, 20)
    reset:SetScript("OnClick", function() Doll:ClearAll() end)

    self:Refresh()
end

-- ============================================================
-- The wardrobe
-- ============================================================
-- Paging through the sets the class can wear. Wearing one is the same
-- try-on a right-click in the list does, so the readings underneath and
-- the highlights beside it are the ones already there.

function Doll:WearSet(name)
    local _, groups = ns.Score:SetGroups()
    local rows = name and groups[name]
    if not rows then return 0 end
    wipe(self.trying)
    local worn, taken = 0, {}
    for _, e in ipairs(rows) do
        local info = ns.Score:Info(e.id)
        -- One piece per slot. A set offering two rings is offering a
        -- choice, and wearing both in the one slot the doll has is not
        -- something the character could do.
        if info and info.slot and ns.Score:Usable(info) and not taken[info.slot] then
            taken[info.slot] = true
            if self:TryOn(e.id, true) then worn = worn + 1 end
        end
    end
    self.setOn = name
    self:Changed()
    return worn
end

function Doll:StepSet(dir)
    local names = ns.Score:WearableSets()
    if #names == 0 then return end
    local at = 0
    for i, n in ipairs(names) do
        if n == self.setOn then at = i break end
    end
    at = at + dir
    if at < 1 then at = #names elseif at > #names then at = 1 end
    self:WearSet(names[at])
end

function Doll:RefreshPicker()
    if not self.setLabel then return end
    local names = ns.Score:WearableSets()
    local at
    for i, n in ipairs(names) do
        if n == self.setOn then at = i break end
    end
    if at then
        self.setLabel:SetText(("%s  (%d of %d)"):format(self.setOn, at, #names))
        tint(self.setLabel, C.fel)
    elseif #names > 0 then
        -- The column is already headed Wardrobe, so this says what the
        -- arrows are for rather than saying it again.
        self.setLabel:SetText(("Pick a set  (%d)"):format(#names))
        tint(self.setLabel, C.muted)
    else
        self.setLabel:SetText("No sets for this class")
        tint(self.setLabel, C.muted)
    end
end
