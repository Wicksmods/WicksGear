-- Wick's Gear
-- UI.lua: the window.

local ADDON, ns = ...
if not WickCore then return end   -- said once in Core.lua
local Core = WickCore
local Chrome = Core.Chrome
local C = Chrome.Colors

local UI = {}
ns.UI = UI

-- A row is three lines now: name, stats, source. Headers keep one, so
-- rows are placed off a running cursor rather than index times height.
local ROW_H = 50
local HEAD_H = 22
local ICON_H = 38
local TAB_H = 22
-- Two columns. The lists take the left and keep their tabs; the doll
-- and the stats hold the right and are always on, so trying something
-- on never costs you your place in the list.
--
-- Sixty/forty off the window width, rather than the window being
-- derived from the narrowest the doll could be squeezed into. The doll
-- spends what it is given on the character model, which is the part
-- worth the room.
--
-- 520 high: the stacked doll runs to 426 points and the "Take it all
-- off" button owns the bottom 24, which 500 does not clear.
local GUTTER = 10
local WIDTH, HEIGHT = 860, 673
local COMPARE_W = math.floor(WIDTH * 0.4) - GUTTER * 2

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
    -- The name keeps its quality colour when the row is usable; the
    -- caller sets it, so only the unusable case is forced here.
    if not usable then tint(row.left, UNUSABLE) end
    tint(row.stats, usable and C.fel or UNUSABLE)
    tint(row.mid, usable and C.muted or UNUSABLE)
    tint(row.right, usable and C.muted or UNUSABLE)
end

-- ============================================================
-- Rows
-- ============================================================

-- What a click on an item row does.
--
-- Bound by name rather than written inline, because rows are pooled: one
-- used as a group header carries the header's toggle, and when that index
-- is drawn as an item again it has to be given this back. Rebinding on
-- every draw is cheaper than remembering which rows were headers.
--
--   click        our own viewer, in the column beside the list
--   ctrl-click   the game's dressing room
--   shift-click  the item into the chat box
function UI.RowClick(s, button)
    if not s.itemID then return end

    if IsShiftKeyDown() and ChatEdit_InsertLink then
        -- s.link may be the bare "item:id" stand-in used for weighing,
        -- which is not a chat link, so ask for a real one.
        local link, source = ns.Score:ChatLink(s.itemID)
        if not link then
            ns.A:Print("no link for that one: the client has never seen it and it is not in our data either.")
            return
        end
        -- InsertLink puts the text in the open chat box and answers false
        -- when there is not one. Saying so beats looking broken.
        if not ChatEdit_InsertLink(link) then
            ns.A:Print("open the chat box first, then shift-click.")
        elseif source == "built" then
            ns.A:Print("the client has not met that item, so this link is ours. Shift-click again in a moment for the real one.")
        end
        return
    end

    if IsControlKeyDown and IsControlKeyDown() then
        -- The game already has somewhere to look at a piece on your own
        -- model, so use it rather than building a second one.
        local link = ns.Score:ChatLink(s.itemID)
        local shown = false
        if link then
            for _, fn in ipairs({ "DressUpItemLink", "DressUpLink" }) do
                local f = rawget(_G, fn)
                if f and pcall(f, link) then shown = true break end
            end
        end
        if not shown then ns.A:Print("the dressing room would not take that one.") end
        return
    end

    -- Plain click, either button: on in our own viewer, which is sitting
    -- next to the list rather than behind a tab, so the list stays put
    -- and you can keep going down it. The row lights up to say it is on
    -- the doll, so clicking a lit one is how you take it off again.
    if ns.Doll:IsTrying(s.itemID) then
        ns.Doll:Untry(s.itemID)
    else
        ns.Doll:TryOn(s.itemID)
    end
end

local function acquire(pane, i)
    pane.rows = pane.rows or {}
    local r = pane.rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, pane.list)
    r:SetHeight(ROW_H)

    -- Every other item row, so three lines read as one block instead
    -- of as three loose lines next to three more.
    r.stripe = Chrome:Texture(r, "BACKGROUND", C.shadow)
    r.stripe:SetAllPoints()
    r.stripe:SetAlpha(0.5)
    r.stripe:Hide()

    -- A group is a group, not an item with less to say.
    r.headBg = Chrome:Texture(r, "BACKGROUND", C.shadow)
    r.headBg:SetAllPoints()
    r.headBg:Hide()
    r.headRule = Chrome:Texture(r, "BORDER", C.border)
    r.headRule:SetPoint("BOTTOMLEFT")
    r.headRule:SetPoint("BOTTOMRIGHT")
    r.headRule:SetHeight(1)
    r.headRule:Hide()

    -- Behind everything: the wash that says this one is on the doll.
    r.sel = Chrome:Texture(r, "BACKGROUND", C.fel)
    r.sel:SetPoint("TOPLEFT", 1, -1)
    r.sel:SetPoint("BOTTOMRIGHT", -1, 1)
    r.sel:SetAlpha(0.10)
    r.sel:Hide()
    r.selEdge = Chrome:Texture(r, "BORDER", C.fel)
    r.selEdge:SetPoint("TOPLEFT", 0, -1)
    r.selEdge:SetPoint("BOTTOMLEFT", 0, 1)
    r.selEdge:SetWidth(2)
    r.selEdge:Hide()

    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(ICON_H, ICON_H)
    r.icon:SetPoint("TOPLEFT", 5, -6)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    -- The chrome the rest of the suite puts round things, and it stops
    -- the art bleeding into the background at the edges.
    r.iconEdge = Chrome:Texture(r, "BORDER", C.border)
    r.iconEdge:SetPoint("TOPLEFT", r.icon, "TOPLEFT", -1, 1)
    r.iconEdge:SetPoint("BOTTOMRIGHT", r.icon, "BOTTOMRIGHT", 1, -1)
    r.iconEdge:Hide()

    -- The rows are clickable and nothing said so.
    r.hl = r:CreateTexture(nil, "HIGHLIGHT")
    r.hl:SetAllPoints()
    r.hl:SetColorTexture(1, 1, 1, 0.06)

    -- Line one: the name, in the colour the game would print it.
    r.left = Chrome:Text(r, 12)
    r.left:SetPoint("TOPLEFT", ICON_H + 12, -7)
    r.left:SetJustifyH("LEFT")
    r.left:SetWordWrap(false)

    -- The score sits at the right edge with a lane of its own, and the
    -- source fills whatever is between the name and it. Fixed widths
    -- here meant that in a narrow pane the source ran under the score
    -- and both became unreadable: "Ragef" over "+11".
    r.right = Chrome:Text(r, 12, C.fel)
    r.right:SetPoint("TOPRIGHT", -6, -7)
    r.right:SetWidth(58)
    r.right:SetJustifyH("RIGHT")

    -- A header's second column, on the header's own line. Items leave
    -- it empty, and an empty font string with no width takes no room,
    -- so the name can anchor to it either way.
    r.note2 = Chrome:Text(r, 10, C.muted)
    r.note2:SetPoint("TOPRIGHT", r.right, "TOPLEFT", -8, 0)
    r.note2:SetJustifyH("RIGHT")
    r.note2:SetWordWrap(false)

    -- Now that both exist, stop the name before them.
    r.left:SetPoint("RIGHT", r.note2, "LEFT", -6, 0)

    -- Line two: what it gives. Line three: where it comes from.
    r.stats = Chrome:Text(r, 10, C.fel)
    r.stats:SetPoint("TOPLEFT", ICON_H + 12, -22)
    r.stats:SetPoint("RIGHT", r.right, "LEFT", -6, 0)
    r.stats:SetJustifyH("LEFT")
    r.stats:SetWordWrap(false)

    r.mid = Chrome:Text(r, 10, C.muted)
    r.mid:SetPoint("TOPLEFT", ICON_H + 12, -35)
    r.mid:SetPoint("RIGHT", r.right, "LEFT", -6, 0)
    r.mid:SetJustifyH("LEFT")
    r.mid:SetWordWrap(false)

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
    r:SetScript("OnClick", UI.RowClick)
    -- Our own drag, between our own frames: the row puts an id down and
    -- a paperdoll slot picks it up.
    r:SetScript("OnDragStart", function(s) UI.dragging = s.itemID end)
    r:SetScript("OnDragStop", function() UI.dragging = nil end)
    pane.rows[i] = r
    return r
end

local function clear(pane)
    for _, r in ipairs(pane.rows or {}) do r:Hide() end
    pane.cursor = 0
    pane.banded = false
end

-- Rows are pooled and serve two jobs. A header is one line, so the two
-- lines an item uses have to be emptied, not just left behind: a font
-- string is not clipped by its frame and would go on drawing over
-- whatever is placed underneath.
-- Lit when the piece is on the doll. Both fillers call it, so a row
-- that was previewed last draw does not stay lit when it is reused.
local function setPreviewed(r, on)
    r.previewed = on and true or false
    r.sel:SetShown(r.previewed)
    r.selEdge:SetShown(r.previewed)
end

local function asHeader(r)
    setPreviewed(r, false)
    r.stripe:Hide()
    r.headBg:Show()
    r.headRule:Show()
    r.iconEdge:Hide()
    r.stats:SetText("")
    r.mid:SetText("")
    r.icon:SetTexture(nil)
    r.icon:SetDesaturated(false)
    r.icon:SetAlpha(1)
    r.dimmed = nil
    r.itemID, r.link, r.note = nil, nil, nil
end

local function asItem(r)
    r.note2:SetText("")
    r.headBg:Hide()
    r.headRule:Hide()
    r.iconEdge:Show()
    setPreviewed(r, ns.Doll:IsTrying(r.itemID))
end

-- Put a row at the bottom of what is drawn so far and move the cursor
-- past it. Fixed heights would mean a group header taking three lines
-- of room to say one word.
local function place(pane, r, h)
    pane.cursor = pane.cursor or 0
    -- Banding is per item row, so a header does not take a turn and
    -- leave two same-shaded rows against each other underneath it.
    if h == ROW_H then
        pane.banded = not pane.banded
        r.stripe:SetShown(pane.banded)
    end
    r:SetHeight(h)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", 0, -pane.cursor)
    r:SetPoint("TOPRIGHT", 0, -pane.cursor)
    pane.cursor = pane.cursor + h
    r:Show()
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
                local name = S:NameFor(cand.entry.id) or "loading..."
                r.left:SetText(("|cff8a8270%s|r %s"):format(S.SLOT_NAME[slot] or "?", name))
                local qc = S:QualityRGB(cand.entry.id)
                r.left:SetTextColor(qc[1], qc[2], qc[3])
                r.stats:SetText(S:StatLine(cand.entry.id))
                r.mid:SetText(("%s  %s%s"):format(cand.dungeon, cand.entry.how,
                    cand.entry.from and (" from " .. cand.entry.from) or ""))
                -- Rounded to a whole number before the sign goes on.
                -- "%+.0f" on anything between minus a half and zero
                -- prints "-0", which reads as a downgrade that is not
                -- one.
                local whole = math.floor(delta + 0.5)
                if whole == 0 then whole = 0 end
                r.right:SetText(("%+d"):format(whole))
                -- An empty slot is still a gain, so it is signed like
                -- the rest rather than printed bare, and always lit:
                -- anything beats nothing.
                asItem(r)
                tint(r.right, (have == 0 or whole > 0) and C.fel or C.muted)
                place(pane, r, ROW_H)
            end
        end
    end

    pane.list:SetHeight(math.max(1, pane.cursor or 0))
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

-- Item, boss or quest, slot, and the dungeon it is in. All four, because
-- "boots", "Taragaman" and "Ragefire" are all things someone types into a
-- box that sits above a list of loot.
local function matches(entry, dungeon, needle)
    if not needle or needle == "" then return true end
    local name = ns.Score:NameFor(entry.id) or entry.name or ""
    for _, field in ipairs({ name, entry.from or "", entry.slot or "", dungeon }) do
        if field:lower():find(needle, 1, true) then return true end
    end
    return false
end

-- The four ways into the same pile of gear. Each returns an ordered list
-- of group names and a lookup from group to its rows, so the fill code
-- below does not care which source it is drawing.
UI.SOURCES = { "dungeons", "crafted", "quests", "sets" }
UI.SOURCE_LABEL = { dungeons = "Dungeons", crafted = "Crafted",
                    quests = "Quests", sets = "Sets" }

-- Built once and kept, because walking every table to find set members
-- on each keystroke would be work for nothing: the tables never change
-- after load.
local setsCache
local function bySet()
    if setsCache then return setsCache end
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
    setsCache = groups
    return groups
end

function UI:Groups(source)
    if source == "crafted" then
        return ns.CRAFTED_ORDER or {}, ns.CRAFTED or {}
    elseif source == "quests" then
        return ns.QUESTS_ORDER or {}, ns.QUESTS or {}
    elseif source == "sets" then
        local groups = bySet()
        local order = {}
        for name in pairs(groups) do order[#order + 1] = name end
        table.sort(order)
        return order, groups
    end
    local order, groups = {}, {}
    for _, name in ipairs(ns.DUNGEON_ORDER or {}) do
        local d = ns.DUNGEONS[name]
        if d then order[#order + 1] = name; groups[name] = d.items end
    end
    return order, groups
end

function UI:SetSource(source)
    self.source = source
    self.search = nil
    local pane = self.panes and self.panes.browse
    if pane and pane.search then pane.search:SetText("") end
    if pane then pane.open = {} end
    self:Refresh()
end

function UI:FillBrowse()
    local pane = self.panes.browse
    clear(pane)
    local S = ns.Score
    local i = 0
    local source = self.source or "dungeons"
    local order, groups = self:Groups(source)

    local needle = (self.search or ""):lower()
    if needle == "" then needle = nil end

    if pane.search then
        pane.search:Show()
        pane.searchHint:SetShown((pane.search:GetText() or "") == "")
    end
    for key, b in pairs(pane.sourceBtns or {}) do
        b:Show()
        b:SetAlpha(key == source and 1 or 0.55)
    end
    if pane.equippable then pane.equippable:Show() end
    local onlyFits = ns.db().onlyEquippable == true

    -- Whether this character could wear it at all. Asked once per row and
    -- again to decide whether a group has anything left worth opening.
    local function fits(entry)
        if not onlyFits then return true end
        local info = S:Info(entry.id)
        -- An item the client has not described yet is kept: hiding it
        -- would make the list shrink as the answers arrive, which reads
        -- as the addon losing things.
        if not info then return true end
        return S:Usable(info) and true or false
    end

    -- One row for an item, wherever it came from. The middle column says
    -- the thing that is worth knowing about it in this source: the boss
    -- for a drop, the skill for a recipe, the group for a set.
    local function itemRow(entry, group)
        local info = S:Info(entry.id)
        i = i + 1
        local r = acquire(pane, i)
        r.itemID = entry.id
        r.link = S:LinkFor(entry.id)
        r.note = nil
        r.icon:SetTexture(info and info.icon or nil)
        r.left:SetText(S:NameFor(entry.id) or entry.name or "loading...")
        local qc = S:QualityRGB(entry.id)
        r.left:SetTextColor(qc[1], qc[2], qc[3])
        r.stats:SetText(S:StatLine(entry.id))
        -- Where it comes from, and what it wants of you.
        local where
        if entry.skill then where = ("skill %d"):format(entry.skill)
        elseif entry.from then where = entry.from
        elseif entry.how == "quest" then where = "quest reward"
        else where = group or "" end
        local req = entry.req or 0
        r.mid:SetText(req > 0 and ("%s  req %d"):format(where, req) or where)
        r.right:SetText("")
        setUsable(r, (info and S:Usable(info)) and true or false)
        -- Take the handler back: this row may have been a group header
        -- last time it was drawn, and would still be carrying its toggle.
        asItem(r)
        r:SetScript("OnClick", UI.RowClick)
        place(pane, r, ROW_H)
    end

    -- Searching flattens the list. A collapsed group hiding the match is
    -- the opposite of searching.
    if needle then
        local found = 0
        for _, group in ipairs(order) do
            for _, entry in ipairs(groups[group] or {}) do
                if matches(entry, group, needle) and fits(entry) then
                    found = found + 1
                    itemRow(entry, group)
                end
            end
        end
        pane.list:SetHeight(math.max(1, pane.cursor or 0))
        pane.empty:SetShown(found == 0)
        if found == 0 then
            pane.empty:SetText("Nothing matches. Try a slot, a name, or where it comes from.")
        end
        pane.head:SetText(("|cff8a8270%d match%s in %s. Clear the box to go back to the list.|r")
            :format(found, found == 1 and "" or "es", UI.SOURCE_LABEL[source]:lower()))
        return
    end

    for _, group in ipairs(order) do
        local rows = groups[group]
        if onlyFits and rows then
            local keep = {}
            for _, e in ipairs(rows) do if fits(e) then keep[#keep + 1] = e end end
            rows = keep
        end
        if rows and #rows > 0 then
            i = i + 1
            local head = acquire(pane, i)
            asHeader(head)
            -- Undo every mark setUsable leaves, not most of them. A row
            -- that was a dimmed item last time it was drawn kept its grey
            -- on the middle column and the name, so one dungeon in the
            -- list looked disabled for no reason.
            tint(head.left, C.text)
            tint(head.note2, C.muted)
            head.left:SetText(("|cff4FC778%s|r"):format(group))

            -- Only a dungeon has a level bracket. A range worked out from
            -- the loot is not the dungeon's own, so it does not get to
            -- look like one.
            local d = source == "dungeons" and ns.DUNGEONS[group]
            if d then
                head.note2:SetText(d.levelsDerived and (d.levels .. "?") or d.levels)
            else
                head.note2:SetText("")
            end
            -- On the Sets tab the count that matters is how much of it
            -- you are wearing, not how many pieces exist.
            local prog = source == "sets" and S:SetProgress(group)
            if prog then
                head.right:SetText(("%d/%d"):format(prog.worn, prog.total))
                tint(head.right, prog.worn > 0 and C.fel or C.muted)
                if prog.next then
                    head.note2:SetText(("next at %d"):format(prog.next.pieces))
                elseif #prog.earned > 0 then
                    head.note2:SetText("all bonuses")
                end
            else
                head.right:SetText(("%d"):format(#rows))
                tint(head.right, C.muted)
            end
            place(pane, head, HEAD_H)

            if pane.open[group] then
                local want = {}
                for _, entry in ipairs(rows) do want[#want + 1] = entry.id end
                ns.Score:WantFirst(want)
                for _, entry in ipairs(rows) do itemRow(entry, group) end
                -- The bonuses themselves used to be rows here, in a
                -- column sized for one line of item name, carrying three
                -- lines of bonus text. They wrapped into the row below.
                -- Earned ones are shown with the stats, where a thing
                -- you are currently getting belongs; the rest are in the
                -- tooltip. The header still says how much you are
                -- wearing and what the next bonus needs.
            end

            head:SetScript("OnClick", function()
                pane.open[group] = not pane.open[group]
                UI:FillBrowse()
            end)
        end
    end

    pane.list:SetHeight(math.max(1, pane.cursor or 0))
    pane.empty:Hide()
    -- What this draw actually produced, for /wgear data. An empty view
    -- looks the same whether the source had no groups or the rows were
    -- built and put somewhere invisible.
    self.lastFill = { source = source, groups = #order, rows = i,
                      open = 0, filtered = onlyFits }
    for _ in pairs(pane.open or {}) do
        self.lastFill.open = self.lastFill.open + 1
    end
    local what = source == "dungeons" and "a dungeon"
        or source == "crafted" and "a profession"
        or source == "quests" and "a zone"
        or "a set"
    pane.head:SetText(("|cff8a8270Click %s to open it. Darkened items you cannot use.|r")
        :format(what))
end


-- ============================================================
-- Frame
-- ============================================================

-- How far down the list starts. Browse carries a strip of source
-- buttons and a search box above it; the other panes do not, and should
-- not be pushed down for a strip they never show.
local STRIP_H = 22

local function makePane(parent, plain, withStrip)
    local pane = CreateFrame("Frame", nil, parent)
    local top = Chrome.HEADER_H + TAB_H + 26 + (withStrip and STRIP_H or 0)
    pane:SetPoint("TOPLEFT", 10, -top)
    -- Stop short of the compare column rather than running under it.
    pane:SetPoint("BOTTOMRIGHT", -(COMPARE_W + GUTTER * 2), 10)
    pane:Hide()

    pane.head = Chrome:Text(parent, 10, C.muted)
    pane.head:SetPoint("TOPLEFT", 12, -Chrome.HEADER_H - TAB_H - 10
        - (withStrip and STRIP_H or 0))
    -- Browse keeps the Equippable toggle on this line, so the text has
    -- to stop before it rather than run underneath.
    pane.head:SetWidth(WIDTH - COMPARE_W - GUTTER * 3 - 24 - (withStrip and 106 or 0))
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

    -- The search box sits in the header strip rather than the scrolling
    -- area, so it stays put while the list moves under it.
    -- Only Browse has sources to switch between, or a list long enough
    -- to want searching. Building the strip for every pane put two sets
    -- of buttons on the same parent at the same point.
    if withStrip then
    -- Parented to the pane, anchored to the panel. On the panel they
    -- stayed visible on Upgrades and Compare, because only the pane and
    -- its head are shown and hidden when a tab changes; on the pane they
    -- follow the tab without Select having to know they exist.
    local search = CreateFrame("EditBox", nil, pane)
    search:SetSize(150, 16)
    -- The pane's right edge, not the panel's. Anchored to the panel
    -- these sat over the compare column, which is where the right edge
    -- of the window now is. The pane already stops short of it, so
    -- following the pane keeps them in the list's half whatever the
    -- split is set to. 40 lifts them out of the pane and into the strip
    -- above it: the pane starts 26 + STRIP_H down and the strip sits 8.
    -- Off the divider. The pane's right edge is where the compare
    -- column starts, and a box sitting hard against it reads as part of
    -- the rule rather than as part of the list.
    search:SetPoint("TOPRIGHT", pane, "TOPRIGHT", -10, 18 + STRIP_H)
    search:SetAutoFocus(false)
    search:SetFontObject("GameFontHighlightSmall")
    search:SetTextInsets(4, 4, 0, 0)
    Chrome:Texture(search, "BACKGROUND", C.shadow):SetAllPoints()
    Chrome:AddBorder(search)
    search:SetScript("OnTextChanged", function(e)
        UI.search = e:GetText()
        if UI.Refresh then UI:Refresh() end
    end)
    search:SetScript("OnEscapePressed", function(e) e:SetText(""); e:ClearFocus() end)
    search:SetScript("OnEnterPressed", function(e) e:ClearFocus() end)
    search:Hide()
    pane.search = search
    pane.searchHint = Chrome:Text(search, 10, C.muted)
    pane.searchHint:SetPoint("LEFT", 5, 0)
    pane.searchHint:SetText("search")

    -- A button per source, left of the search box.
    pane.sourceBtns = {}
    local sx = 0
    for _, key in ipairs(UI.SOURCES) do
        local b = Chrome:Button(pane, UI.SOURCE_LABEL[key], 60, 16)
        b:SetPoint("TOPLEFT", pane, "TOPLEFT", sx, 18 + STRIP_H)
        sx = sx + 63
        b:SetScript("OnClick", function() UI:SetSource(key) end)
        pane.sourceBtns[key] = b
        b:Hide()
    end

    -- Dimming is enough for a dungeon's nine items and useless against
    -- a profession's four hundred, most of which are the wrong armour
    -- type for you.
    pane.equippable = Chrome:Check(pane, "Equippable",
        function() return ns.db().onlyEquippable == true end,
        function(v) ns.db().onlyEquippable = v; UI:Refresh() end)
    -- Chrome:Check is 220 wide by default with the box at its left edge,
    -- so anchored right the box lands in the middle of the panel and the
    -- help text runs into it. Sized to what it actually draws.
    pane.equippable:SetWidth(100)
    pane.equippable:SetPoint("TOPRIGHT", pane, "TOPRIGHT", -10, STRIP_H)
    pane.equippable:Hide()
    end

    pane.empty = Chrome:Text(pane, 11, C.muted)
    pane.empty:SetPoint("TOPLEFT", 2, -4)
    pane.empty:SetWidth(WIDTH - COMPARE_W - GUTTER * 3 - 30)
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
    for _, def in ipairs({ { "upgrades", "Upgrades" }, { "browse", "Browse" } }) do
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
        self.panes[def[1]] = makePane(p, false, def[1] == "browse")
        x = x + 84
    end

    -- The compare column. Still panes.compare, so everything that asks
    -- for it by name still finds it; it simply never hides now.
    local cmp = CreateFrame("Frame", nil, p)
    cmp:SetPoint("TOPRIGHT", -GUTTER, -Chrome.HEADER_H - TAB_H - 4)
    cmp:SetPoint("BOTTOMRIGHT", -GUTTER, 10)
    cmp:SetWidth(COMPARE_W)
    self.panes.compare = cmp

    -- A rule between the two, so the split reads as one window in two
    -- parts rather than two windows that happen to touch.
    local rule = Chrome:Texture(p, "ARTWORK", C.border)
    rule:SetPoint("TOPRIGHT", cmp, "TOPLEFT", -GUTTER + 1, 6)
    rule:SetPoint("BOTTOMRIGHT", cmp, "BOTTOMLEFT", -GUTTER + 1, 0)
    rule:SetWidth(1)

    cmp.head = Chrome:Text(cmp, 10, C.muted)
    cmp.head:SetPoint("TOPLEFT", 4, 14)
    cmp.head:SetText("Trying on")
    -- It is not a tab any more, so nothing else will ever show it.
    cmp:Show()

    p:SetScript("OnShow", function() UI:Refresh() end)
    self.panel = p
    self:Select("upgrades")
    return p
end

function UI:Select(which)
    -- Compare is not a tab any more. Asking for it used to be how a row
    -- click showed you the doll, and callers still do; the doll is
    -- always up now, so there is nothing to switch to.
    if which == "compare" then self:Refresh() return end
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
    if self.active == "browse" then self:FillBrowse() else self:FillUpgrades() end
    -- The right column is always on, so it is always redrawn.
    if ns.Doll:Ensure() then ns.Doll:Refresh() end
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
        -- Item data has arrived, so a set the client could not describe
        -- a moment ago may be describable now.
        ns.Score:ForgetSetCache()
        if not (UI.panel and UI.panel:IsShown()) then return end
        if UI.active == "browse" then UI:FillBrowse() else UI:FillUpgrades() end
        if ns.Doll:Ensure() then ns.Doll:Refresh() end
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
