-- Wick's Gear
-- UI.lua: the window.

local ADDON, ns = ...
local Core = WickCore
local Chrome = Core.Chrome
local C = Chrome.Colors

local UI = {}
ns.UI = UI

local ROW_H = 20
local TAB_H = 22
local WIDTH, HEIGHT = 520, 420

local function tint(fs, c) fs:SetTextColor(c[1], c[2], c[3], c[4] or 1) end

-- Muted is the colour of a secondary label, not of something unavailable,
-- and at this size the two read the same. Gear the class cannot use needs
-- to be obvious at a glance, so it goes darker than any label and loses
-- the colour in its icon as well.
local UNUSABLE = { 0.34, 0.31, 0.28, 1 }

local function setUsable(row, usable)
    row.dimmed = not usable
    row.icon:SetDesaturated(not usable)
    row.icon:SetAlpha(usable and 1 or 0.3)
    tint(row.left, usable and C.text or UNUSABLE)
    tint(row.mid, usable and C.muted or UNUSABLE)
    tint(row.right, usable and C.muted or UNUSABLE)
end

-- ============================================================
-- Rows
-- ============================================================

local function acquire(pane, i)
    pane.rows = pane.rows or {}
    local r = pane.rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, pane.list)
    r:SetHeight(ROW_H)
    r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    r:SetPoint("TOPRIGHT", 0, -(i - 1) * ROW_H)

    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(16, 16)
    r.icon:SetPoint("LEFT", 2, 0)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    r.left = Chrome:Text(r, 11)
    r.left:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
    r.left:SetWidth(190)
    r.left:SetJustifyH("LEFT")

    r.mid = Chrome:Text(r, 10, C.muted)
    r.mid:SetPoint("LEFT", r.left, "RIGHT", 4, 0)
    r.mid:SetWidth(120)
    r.mid:SetJustifyH("LEFT")

    r.right = Chrome:Text(r, 11, C.fel)
    r.right:SetPoint("RIGHT", -4, 0)

    r:SetScript("OnEnter", function(s)
        if not s.link and not s.itemID then return end
        GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
        ns.Score:FillTooltip(GameTooltip, s.itemID, s.link)
        if s.note then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(s.note, 0.5, 0.5, 0.5, true)
        end
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r:RegisterForClicks("AnyUp")
    r:RegisterForDrag("LeftButton")
    r:SetScript("OnClick", function(s, button)
        if button == "RightButton" and not IsShiftKeyDown() then
            if s.itemID then ns.Doll:TryOn(s.itemID) end
            return
        end
        -- Shift-click to link, the way every other list in the game
        -- works. s.link may be the bare "item:id" stand-in used for
        -- weighing, which is not a chat link, so ask for a real one.
        if IsShiftKeyDown() and ChatEdit_InsertLink then
            local link = ns.Score:ChatLink(s.itemID)
            if link then ChatEdit_InsertLink(link)
            else ns.A:Print("no link for that one: the client has never seen it and it is not in our data either.") end
        end
    end)
    -- Our own drag, between our own frames: the row puts an id down and
    -- a paperdoll slot picks it up.
    r:SetScript("OnDragStart", function(s) UI.dragging = s.itemID end)
    r:SetScript("OnDragStop", function() UI.dragging = nil end)
    pane.rows[i] = r
    return r
end

local function clear(pane)
    for _, r in ipairs(pane.rows or {}) do r:Hide() end
end

-- ============================================================
-- Upgrades
-- ============================================================

function UI:FillUpgrades()
    local pane = self.panes.upgrades
    clear(pane)
    local S, db = ns.Score, ns.db()
    local level = UnitLevel("player")
    local cap = (db.maxLevel and db.maxLevel > 0) and db.maxLevel or level

    -- Best candidate per slot, and what you are wearing there.
    local best = {}
    for dungeon, d in pairs(ns.DUNGEONS) do
        for _, entry in ipairs(d.items) do
            if entry.req <= cap then
                local info = S:Info(entry.id)
                if info and info.slot and S:Usable(info) then
                    local link = S:LinkFor(entry.id)
                    local pts, why = S:Value(link, entry.id)
                    if pts > 0 then
                        local cur = best[info.slot]
                        if not cur or pts > cur.pts then
                            best[info.slot] = { pts = pts, why = why, info = info,
                                                entry = entry, dungeon = dungeon, link = link }
                        end
                    end
                end
            end
        end
    end

    local i, shown = 0, 0
    for _, slot in ipairs(S.SLOT_ORDER) do
        local cand = best[slot]
        if cand then
            local have = S:EquippedValue(slot)
            local delta = cand.pts - have
            if not (db.hideWorn and delta <= 0) then
                i = i + 1
                shown = shown + 1
                local r = acquire(pane, i)
                r.itemID, r.link = cand.entry.id, cand.link
                r.note = ("%s, %s%s"):format(cand.dungeon, cand.entry.how,
                    cand.entry.from and (" from " .. cand.entry.from) or "")
                r.icon:SetTexture(cand.info.icon)
                setUsable(r, true)
                local name = S:NameFor(cand.entry.id) or "|cff6a6258loading...|r"
                r.left:SetText(("|cff8a8270%s|r %s"):format(S.SLOT_NAME[slot] or "?", name))
                r.mid:SetText(cand.dungeon)
                if have > 0 then
                    r.right:SetText(("%+.0f"):format(delta))
                    tint(r.right, delta > 0 and C.fel or C.muted)
                else
                    r.right:SetText(("%.0f"):format(cand.pts))
                    tint(r.right, C.fel)
                end
                r:Show()
            end
        end
    end

    pane.list:SetHeight(math.max(1, i * ROW_H))
    pane.empty:SetShown(shown == 0)
    if shown == 0 then
        pane.empty:SetText(db.hideWorn
            and "Nothing here beats what you are wearing. Which is the answer, even if it is a dull one."
            or "Nothing scored yet. If this persists, the item data has not arrived from the server.")
    end
    pane.head:SetText(("%s, level %d  |cff8a8270scored against what you have on|r")
        :format(ns.Score:ClassKey():gsub("_", " "):lower(), level))
end

-- ============================================================
-- Browse
-- ============================================================

function UI:FillBrowse()
    local pane = self.panes.browse
    clear(pane)
    local S = ns.Score
    local i = 0

    for _, dungeon in ipairs(ns.DUNGEON_ORDER) do
        local d = ns.DUNGEONS[dungeon]
        if d then
            i = i + 1
            local head = acquire(pane, i)
            head.itemID, head.link, head.note = nil, nil, nil
            head.icon:SetTexture(nil)
            head.dimmed = nil
            head.icon:SetDesaturated(false)
            head.icon:SetAlpha(1)
            head.left:SetText(("|cff4FC778%s|r"):format(dungeon))
            -- A range worked out from the loot is not the dungeon's
            -- own bracket, so it does not get to look like one.
            head.mid:SetText(d.levelsDerived and (d.levels .. "?") or d.levels)
            head.right:SetText(("%d"):format(#d.items))
            tint(head.right, C.muted)
            head:Show()

            if pane.open[dungeon] then
                -- Looking at a dungeon puts its loot at the front of the
                -- queue, ahead of the thirteen you are not looking at.
                local want = {}
                for _, entry in ipairs(d.items) do want[#want + 1] = entry.id end
                ns.Score:WantFirst(want)
                for _, entry in ipairs(d.items) do
                    local info = S:Info(entry.id)
                    i = i + 1
                    local r = acquire(pane, i)
                    r.itemID = entry.id
                    r.link = S:LinkFor(entry.id)
                    r.note = nil
                    r.icon:SetTexture(info and info.icon or nil)
                    local name = S:NameFor(entry.id) or "|cff6a6258loading...|r"
                    local usable = (info and S:Usable(info)) and true or false
                    r.left:SetText(("   %s"):format(name))
                    r.mid:SetText(entry.from or (entry.how == "quest" and "quest reward" or ""))
                    r.right:SetText(entry.req > 0 and ("req %d"):format(entry.req) or "")
                    setUsable(r, usable)
                    r:Show()
                end
            end

            head:SetScript("OnClick", function()
                pane.open[dungeon] = not pane.open[dungeon]
                UI:FillBrowse()
            end)
        end
    end

    pane.list:SetHeight(math.max(1, i * ROW_H))
    pane.empty:Hide()
    pane.head:SetText("|cff8a8270Click a dungeon to open it. Darkened items your class cannot use.|r")
end

-- ============================================================
-- Frame
-- ============================================================

local function makePane(parent, plain)
    local pane = CreateFrame("Frame", nil, parent)
    pane:SetPoint("TOPLEFT", 10, -Chrome.HEADER_H - TAB_H - 26)
    pane:SetPoint("BOTTOMRIGHT", -10, 10)
    pane:Hide()

    pane.head = Chrome:Text(parent, 10, C.muted)
    pane.head:SetPoint("TOPLEFT", 12, -Chrome.HEADER_H - TAB_H - 10)
    pane.head:SetWidth(WIDTH - 24)
    pane.head:SetJustifyH("LEFT")

    if plain then
        -- The paperdoll lays itself out; it wants no scroll frame.
        pane.head:SetText("")
        return pane
    end

    local clip = CreateFrame("ScrollFrame", nil, pane)
    clip:SetAllPoints()
    local list = CreateFrame("Frame", nil, clip)
    list:SetSize(1, 1)
    clip:SetScrollChild(list)
    clip:EnableMouseWheel(true)
    clip:SetScript("OnMouseWheel", function(f, delta)
        local range = math.max(0, (tonumber(list:GetHeight()) or 0) - (tonumber(f:GetHeight()) or 0))
        if range <= 0 then return end
        f:SetVerticalScroll(math.min(range, math.max(0, (tonumber(f:GetVerticalScroll()) or 0) - delta * ROW_H * 2)))
    end)
    clip:SetScript("OnSizeChanged", function(f) list:SetWidth(f:GetWidth() or 1) end)

    pane.clip, pane.list, pane.open = clip, list, {}
    pane.empty = Chrome:Text(pane, 11, C.muted)
    pane.empty:SetPoint("TOPLEFT", 2, -4)
    pane.empty:SetWidth(WIDTH - 40)
    pane.empty:SetJustifyH("LEFT")
    pane.empty:Hide()
    return pane
end

function UI:Build()
    if self.panel then return self.panel end
    local db = ns.db()
    local p = Chrome:NewPanel("WicksGearPanel", { width = WIDTH, height = HEIGHT })
    p.db = db.window
    p.title:SetText(Chrome:TitleMarkup("Wick's Gear"))
    Chrome:AddBrackets(p)
    Chrome:RestorePosition(p, db.window)

    local strip = CreateFrame("Frame", nil, p)
    strip:SetPoint("TOPLEFT", 1, -Chrome.HEADER_H - 1)
    strip:SetPoint("TOPRIGHT", -1, -Chrome.HEADER_H - 1)
    strip:SetHeight(TAB_H)

    self.panes, self.tabs = {}, {}
    local x = 8
    for _, def in ipairs({ { "upgrades", "Upgrades" }, { "browse", "Browse" }, { "compare", "Compare" } }) do
        local b = CreateFrame("Button", nil, strip)
        b:SetSize(80, TAB_H)
        b:SetPoint("LEFT", x, 0)
        b.lbl = Chrome:Text(b, 11, C.muted)
        b.lbl:SetPoint("CENTER")
        b.lbl:SetText(def[2])
        b.under = Chrome:Texture(b, "OVERLAY", C.fel)
        b.under:SetPoint("BOTTOMLEFT", 8, 0)
        b.under:SetPoint("BOTTOMRIGHT", -8, 0)
        b.under:SetHeight(2)
        b.under:Hide()
        b:SetScript("OnClick", function() UI:Select(def[1]) end)
        self.tabs[def[1]] = b
        self.panes[def[1]] = makePane(p, def[1] == "compare")
        x = x + 84
    end

    p:SetScript("OnShow", function() UI:Refresh() end)
    self.panel = p
    self:Select("upgrades")
    return p
end

function UI:Select(which)
    self.active = which
    for id, b in pairs(self.tabs) do
        local on = id == which
        tint(b.lbl, on and C.fel or C.muted)
        b.under:SetShown(on)
        self.panes[id]:SetShown(on)
        self.panes[id].head:SetShown(on)
    end
    self:Refresh()
end

function UI:Refresh()
    if not self.panel or not self.panel:IsShown() then return end
    -- Draw now with whatever the client already knows, and ask for the
    -- rest in the background. Waiting for all of it is what made this
    -- feel broken: the whole list sat empty for the slowest item.
    ns.Score:Want(ns.AllItemIDs())
    if self.active == "browse" then self:FillBrowse()
    elseif self.active == "compare" then
        if ns.Doll:Ensure() then ns.Doll:Refresh() end
    else self:FillUpgrades() end
end

-- The server sends item data back a few at a time, and whatever had not
-- arrived when the list was drawn would otherwise sit there reading
-- "item 9454" forever. Redraw when more turns up, coalesced so a
-- hundred arrivals in one second are one redraw.
function UI:ItemArrived()
    if not (self.panel and self.panel:IsShown()) then return end
    if self.redrawQueued then return end
    self.redrawQueued = true
    C_Timer.After(0.3, function()
        UI.redrawQueued = nil
        if not (UI.panel and UI.panel:IsShown()) then return end
        if UI.active == "browse" then UI:FillBrowse()
        elseif UI.active == "compare" then
            if ns.Doll:Ensure() then ns.Doll:Refresh() end
        else UI:FillUpgrades() end
    end)
end

function UI:Toggle(which)
    local p = self:Build()
    if which and p:IsShown() and self.active ~= which then
        self:Select(which)
        return
    end
    if p:IsShown() then p:Hide() else
        if which then self.active = which end
        p:Show()
        if which then self:Select(which) end
    end
end

function UI:Init() end
