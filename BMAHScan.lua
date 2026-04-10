local addonName = ...
local BMAHScan = CreateFrame("Frame")

-- Global SavedVariable table (declared in TOC)
BMAHScanDB = BMAHScanDB or {}

-- Filter state (not persisted for now)
BMAHScan.filters = {
    typeSet         = nil,   -- nil = all types, or table { MOUNT=true, ARMOR=true, ... }
    myBidsOnly      = false,
    timeSet         = nil,   -- nil = all times; or table [timeCode]=true
    -- Collected filter (new)
    showCollected   = true,  -- show collected items
    showUncollected = true,  -- show uncollected items
}


local TYPE_OPTIONS = { "MOUNT", "ARMOR", "PET", "WEAPON", "TOY", "CONTAINER", "OTHER" }
local TYPE_LABELS = {
    MOUNT     = "Mount",
    ARMOR     = "Armor",
    PET       = "Pet",
    WEAPON    = "Weapon",
    TOY       = "Toy",
    CONTAINER = "Container",
    OTHER     = "Other",
}

local RADIO_NORMAL    = "Interface\\AddOns\\BMAHScan\\Textures\\BMAHRadio-Normal"
local RADIO_CHECKED   = "Interface\\AddOns\\BMAHScan\\Textures\\BMAHRadio-Checked"
local RADIO_HIGHLIGHT = "Interface\\AddOns\\BMAHScan\\Textures\\BMAHRadio-Highlight"

local function GetTypeLabel(code)
    return TYPE_LABELS[code] or code or ""
end

-- Simple colored prefix for chat messages
local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[BMAHScan]|r " .. tostring(msg))
end

-- Gold-only money formatter (copper -> "XXXXg")
-- add thousands separators
local function CommaValue(amount)
    local formatted = tostring(amount)
    local k
    while true do
        formatted, k = formatted:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
        if k == 0 then break end
    end
    return formatted
end

local function FormatMoney(copper)
    copper = copper or 0
    local gold = math.floor(copper / 10000)
    return CommaValue(gold) .. "g"
end


timeLeftLabels = {
    [0] = "Completed",
    [1] = "Short",
    [2] = "Medium",
    [3] = "Long",
    [4] = "Very Long",
    [5] = "Completed",
}


-- layout constants
local HEADER_HEIGHT      = 18
local ROW_HEIGHT         = 18
local LEFT_PAD           = 10
local RIGHT_PAD          = 10
local COL_SPACING        = 8
-- columns: MyBid | Item (icon+text) | Bid | Time | Bids | Type | Collected
local HIGHBID_COL_WIDTH  = 40   -- "My Bid"
local BID_COL_WIDTH      = 70
local TIME_COL_WIDTH     = 50
local BIDS_COL_WIDTH     = 25
local TYPE_COL_WIDTH     = 50
local COLLECTED_COL_WIDTH = 50

------------------------------------------------------------
-- Layout save/load
------------------------------------------------------------

local function SaveLayout()
    if not BMAHScan.window then return end
    local f = BMAHScan.window

    local point, _, relPoint, xOfs, yOfs = f:GetPoint()
    local width, height = f:GetSize()

    BMAHScanDB = BMAHScanDB or {}
    BMAHScanDB._layout = {
        point   = point,
        relPoint = relPoint,
        x       = xOfs,
        y       = yOfs,
        width   = width,
        height  = height,
    }
end

------------------------------------------------------------
-- Column layout
------------------------------------------------------------

function BMAHScan:UpdateColumnLayout()
    if not self.window or not self.window.scrollFrame or not self.content or not self.headers then
        return
    end

    local scrollWidth = self.window.scrollFrame:GetWidth() or 350
    -- fixed-width columns (everything except item)
    local fixed = HIGHBID_COL_WIDTH +
                  BID_COL_WIDTH + TIME_COL_WIDTH + BIDS_COL_WIDTH +
                  TYPE_COL_WIDTH + COLLECTED_COL_WIDTH +
                  LEFT_PAD + RIGHT_PAD +
                  COL_SPACING * 7  -- 6 gaps between columns + edges

    local itemWidth = scrollWidth - fixed
    if itemWidth < 100 then
        itemWidth = 100
    end

    local headers = self.headers

    local function place(fs, x, width, justify)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", self.content, "TOPLEFT", x, -2)
        fs:SetWidth(width)
        fs:SetJustifyH(justify or "LEFT")
    end

    local x = LEFT_PAD
    place(headers.high, x, HIGHBID_COL_WIDTH, "CENTER")
    x = x + HIGHBID_COL_WIDTH + COL_SPACING

    place(headers.item, x, itemWidth, "LEFT")
    x = x + itemWidth + COL_SPACING

    place(headers.bid,  x, BID_COL_WIDTH, "RIGHT")
    x = x + BID_COL_WIDTH + COL_SPACING

    place(headers.time, x, TIME_COL_WIDTH, "LEFT")
    x = x + TIME_COL_WIDTH + COL_SPACING

    place(headers.bids, x, BIDS_COL_WIDTH, "CENTER")
    x = x + BIDS_COL_WIDTH + COL_SPACING

    place(headers.type, x, TYPE_COL_WIDTH, "LEFT")
    x = x + TYPE_COL_WIDTH + COL_SPACING

    place(headers.collected, x, COLLECTED_COL_WIDTH, "CENTER")

    -- invisible separator under header (we keep it for positioning only)
    if self.headerSep then
        self.headerSep:ClearAllPoints()
        self.headerSep:SetPoint("TOPLEFT", self.content, "TOPLEFT", LEFT_PAD, -HEADER_HEIGHT)
        self.headerSep:SetPoint("TOPRIGHT", self.content, "TOPRIGHT", -RIGHT_PAD, -HEADER_HEIGHT)
    end

    -- rows
    if self.rows then
        for _, row in ipairs(self.rows) do
            local cells = row.cells
            if cells then
                local yOffset = 0

                cells.high:ClearAllPoints()
                cells.item:ClearAllPoints()
                cells.bid:ClearAllPoints()
                cells.time:ClearAllPoints()
                cells.bids:ClearAllPoints()
                cells.type:ClearAllPoints()
                if cells.collected then
                    cells.collected:ClearAllPoints()
                end

                local rx = LEFT_PAD
                cells.high:SetPoint("LEFT", row, "LEFT", rx, yOffset)
                cells.high:SetWidth(HIGHBID_COL_WIDTH)
                rx = rx + HIGHBID_COL_WIDTH + COL_SPACING

                local iconOffset = 0
                if row.iconBtn then
                    row.iconBtn:ClearAllPoints()
                    row.iconBtn:SetPoint("LEFT", row, "LEFT", rx, 0)
                    row.iconBtn:SetSize(ROW_HEIGHT, ROW_HEIGHT)
                    iconOffset = ROW_HEIGHT + 4
                end

                cells.item:SetPoint("LEFT", row, "LEFT", rx + iconOffset, yOffset)
                cells.item:SetWidth(itemWidth - iconOffset)

                rx = rx + itemWidth + COL_SPACING

                cells.bid:SetPoint("LEFT", row, "LEFT", rx, yOffset)
                cells.bid:SetWidth(BID_COL_WIDTH)
                rx = rx + BID_COL_WIDTH + COL_SPACING

                cells.time:SetPoint("LEFT", row, "LEFT", rx, yOffset)
                cells.time:SetWidth(TIME_COL_WIDTH)
                rx = rx + TIME_COL_WIDTH + COL_SPACING

                cells.bids:SetPoint("LEFT", row, "LEFT", rx, yOffset)
                cells.bids:SetWidth(BIDS_COL_WIDTH)
                rx = rx + BIDS_COL_WIDTH + COL_SPACING

                cells.type:SetPoint("LEFT", row, "LEFT", rx, yOffset)
                cells.type:SetWidth(TYPE_COL_WIDTH)
                rx = rx + TYPE_COL_WIDTH + COL_SPACING

                if cells.collected then
                    cells.collected:SetPoint("LEFT", row, "LEFT", rx, yOffset)
                    cells.collected:SetWidth(COLLECTED_COL_WIDTH)
                end
            end
        end
    end
end

------------------------------------------------------------
-- Class color + time-ago helpers
------------------------------------------------------------

local function ColorizeNameByClass(name, classTag)
    if not name or not classTag or not RAID_CLASS_COLORS or not RAID_CLASS_COLORS[classTag] then
        return name or "Unknown"
    end
    local c = RAID_CLASS_COLORS[classTag]
    local r = math.floor((c.r or 1) * 255 + 0.5)
    local g = math.floor((c.g or 1) * 255 + 0.5)
    local b = math.floor((c.b or 1) * 255 + 0.5)
    return string.format("|cff%02x%02x%02x%s|r", r, g, b, name)
end

local function FormatTimeAgoColored(last)
    if not last then
        return "|cffff0000never|r"
    end
    local diff = time() - last
    if diff < 0 then diff = 0 end

    local hours = math.floor(diff / 3600)
    local mins  = math.floor((diff % 3600) / 60)
    local secs  = diff % 60

    local txt = string.format("%dh%02dm%02ds ago", hours, mins, secs)

    local color
    if diff < 4 * 60 then
        color = "|cff00ff00"       -- green
    elseif diff < 30 * 60 then
        color = "|cffffff00"       -- yellow
    else
        color = "|cffff0000"       -- red
    end

    return color .. txt .. "|r"
end

------------------------------------------------------------
-- Collection status helper
------------------------------------------------------------

local function IsItemCollected(category, itemLink)
    if not itemLink or not GetItemInfoInstant then
        return nil
    end

    local itemID = select(1, GetItemInfoInstant(itemLink))
    if not itemID then
        return nil
    end

    -- Mounts
    if category == "MOUNT"
       and C_MountJournal
       and C_MountJournal.GetMountFromItem
       and C_MountJournal.GetMountInfoByID then
        local mountID = C_MountJournal.GetMountFromItem(itemID)
        if mountID then
            local name, spellID, icon, isActive, isUsable, sourceType,
                  isFavorite, isFactionSpecific, faction, shouldHideOnChar,
                  isCollected = C_MountJournal.GetMountInfoByID(mountID)
            if isCollected ~= nil then
                return isCollected and true or false
            end
        end
    -- Toys
    elseif category == "TOY" and PlayerHasToy then
        local hasToy = PlayerHasToy(itemID)
        if hasToy ~= nil then
            return hasToy and true or false
        end
    -- Pets (battle pet items)
    elseif category == "PET"
       and C_PetJournal
       and C_PetJournal.GetPetInfoByItemID
       and C_PetJournal.GetNumCollectedInfo then
        local name, icon, petType, creatureID, sourceText, description,
              isWild, canBattle, tradeable, unique, obtainable,
              displayID, speciesID = C_PetJournal.GetPetInfoByItemID(itemID)
        if speciesID then
            local numCollected = C_PetJournal.GetNumCollectedInfo(speciesID)
            if type(numCollected) == "number" then
                return numCollected > 0
            end
        end
    -- Transmog (armor/weapons)
    elseif (category == "ARMOR" or category == "WEAPON")
       and C_TransmogCollection
       and C_TransmogCollection.PlayerHasTransmog then
        local hasTransmog = C_TransmogCollection.PlayerHasTransmog(itemID)
        if hasTransmog ~= nil then
            return hasTransmog and true or false
        end
    end

    -- unknown / not applicable
    return nil
end

------------------------------------------------------------
-- Window + headers + filters UI
------------------------------------------------------------

local function CreateWindow()
    if BMAHScan.window then
        return
    end

    local f = CreateFrame("Frame", "BMAHScanWindow", UIParent, "BackdropTemplate")

    -- size & position from saved layout, or defaults
    local layout = BMAHScanDB and BMAHScanDB._layout or nil
    if layout and layout.width and layout.height then
        f:SetSize(layout.width, layout.height)
    else
        f:SetSize(520, 340)
    end

    f:SetFrameStrata("DIALOG")

    f:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile     = true, tileSize = 32, edgeSize = 16,
        insets   = { left = 4, right = 4, top = 4, bottom = 4 },
    })

    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SaveLayout()
    end)

    -- Resizable (Retail)
    f:SetResizable(true)
    f:SetResizeBounds(380, 260)

    local resize = CreateFrame("Button", nil, f)
    resize:SetPoint("BOTTOMRIGHT", -4, 4)
    resize:SetSize(16, 16)
    resize:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resize:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resize:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")

    resize:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            f:StartSizing("BOTTOMRIGHT")
            f.isSizing = true
        end
    end)

    resize:SetScript("OnMouseUp", function(self)
        if f.isSizing then
            f:StopMovingOrSizing()
            f.isSizing = false
            SaveLayout()
        end
    end)

    -- Position AFTER size so it anchors correctly
    if layout and layout.point then
        f:ClearAllPoints()
        f:SetPoint(layout.point, UIParent, layout.relPoint or layout.point, layout.x or 0, layout.y or 0)
    else
        f:SetPoint("CENTER")
    end

    -- Close button
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)

    -- Title
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOP", 0, -8)
    f.title:SetText("Black Market Scan")

    --------------------------------------------------------
    -- Filters row
    --------------------------------------------------------

    -- Filter button styled like vendor dropdown
    local typeBtn = CreateFrame("Button", "BMAHScanFilterButton", f, "UIMenuButtonStretchTemplate")
    typeBtn:SetSize(90, 22)
    typeBtn:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -26)
    typeBtn:SetText("Filter")

    function BMAHScan:UpdateTypeButtonLabel()
        typeBtn:SetText("Filter")
    end
    BMAHScan:UpdateTypeButtonLabel()

    -- Red "clear filters" button that only shows when filters are active
    local clearBtn = CreateFrame("Button", nil, f)
    clearBtn:SetSize(20, 20)
    clearBtn:SetPoint("LEFT", typeBtn, "RIGHT", 4, 0)
    clearBtn:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
    clearBtn:SetHighlightTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Highlight")
    clearBtn:SetPushedTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Down")
    clearBtn:Hide()
    BMAHScan.clearFiltersButton = clearBtn

    -- Dropdown frame
    local drop = CreateFrame("Frame", nil, f, "BackdropTemplate")
    drop:SetPoint("TOPLEFT", typeBtn, "BOTTOMLEFT", 0, -2)
    local dropWidth = math.max(typeBtn:GetWidth() + 60, 260)
    drop:SetWidth(dropWidth)
    drop:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile     = true, tileSize = 16, edgeSize = 16,
        insets   = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    drop:SetFrameStrata("FULLSCREEN_DIALOG")
    drop:SetToplevel(true)
    drop:SetFrameLevel(f:GetFrameLevel() + 10)
    drop:Hide()
    BMAHScan.typeDropdown = drop

    -- helper to style checkboxes cleaner
    local function StyleCheckButton(cb)
        cb:SetSize(20, 20)

        local textFS = cb.text or cb.Text
        if textFS then
            textFS:ClearAllPoints()
            textFS:SetPoint("LEFT", cb, "RIGHT", 4, 0)
            textFS:SetFontObject("GameFontHighlightSmall")
        end

        local checked = cb:GetCheckedTexture()
        if checked then
            checked:SetDesaturated(false)
            checked:SetVertexColor(1, 1, 0.1) -- yellow-ish check
            checked:SetDrawLayer("ARTWORK")
        end

        local normal = cb:GetNormalTexture()
        if normal then
            normal:SetVertexColor(1, 1, 1, 0.9)
        end
    end

    -- similar styling for radio buttons so they match
    local function StyleRadioButton(rb)

        -- keep default Blizzard radio art, just tweak size + text
        rb:SetSize(18, 18)

        local textFS = rb.text or rb.Text
        if textFS then
            textFS:ClearAllPoints()
            textFS:SetPoint("LEFT", rb, "RIGHT", 4, 0)
            textFS:SetFontObject("GameFontHighlightSmall")
        end
    end

    ------------------------------------------------
    -- LEFT COLUMN: type checkboxes
    ------------------------------------------------

    local showAll = CreateFrame("CheckButton", nil, drop, "UICheckButtonTemplate")
    showAll.text:SetText("Show All types")
    showAll:SetPoint("TOPLEFT", drop, "TOPLEFT", 8, -8)
    StyleCheckButton(showAll)

    local checkboxes = {}
    local prevLeft = showAll
    for _, code in ipairs(TYPE_OPTIONS) do
        local cb = CreateFrame("CheckButton", nil, drop, "UICheckButtonTemplate")
        cb.typeCode = code
        cb.text:SetText(GetTypeLabel(code))
        cb:SetPoint("TOPLEFT", prevLeft, "BOTTOMLEFT", 0, 0)
        StyleCheckButton(cb)
        table.insert(checkboxes, cb)
        prevLeft = cb
    end

    ------------------------------------------------
    -- RIGHT COLUMN: ownership + time radios
    ------------------------------------------------

    local rightX = dropWidth * 0.5

    local ownLabel = drop:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ownLabel:SetPoint("TOPLEFT", drop, "TOPLEFT", rightX, -8)
    ownLabel:SetText("Ownership")

    local allRadio = CreateFrame("CheckButton", nil, drop, "UIRadioButtonTemplate")
    allRadio.text:SetText("All auctions")
    allRadio:SetPoint("TOPLEFT", ownLabel, "BOTTOMLEFT", 0, 0)
    StyleRadioButton(allRadio)

    local myRadio = CreateFrame("CheckButton", nil, drop, "UIRadioButtonTemplate")
    myRadio.text:SetText("My bids")
    myRadio:SetPoint("TOPLEFT", allRadio, "BOTTOMLEFT", 0, 0)
    StyleRadioButton(myRadio)


local timeLabel = drop:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
timeLabel:SetPoint("TOPLEFT", myRadio, "BOTTOMLEFT", 0, -4)
timeLabel:SetText("Time left")

-- "All time" master checkbox
local timeAll = CreateFrame("CheckButton", nil, drop, "UICheckButtonTemplate")
timeAll.text:SetText("All time")
timeAll:SetPoint("TOPLEFT", timeLabel, "BOTTOMLEFT", 0, 0)
StyleCheckButton(timeAll)

-- Individual time-range checkboxes
local timeChecks = {}
local timeDefs = {
    { key = 0, label = "Completed" }, -- moved to top
    { key = 1, label = "Short"     },
    { key = 2, label = "Medium"    },
    { key = 3, label = "Long"      },
    { key = 4, label = "Very Long" },
}

for i, info in ipairs(timeDefs) do
    local cb = CreateFrame("CheckButton", nil, drop, "UICheckButtonTemplate")
    cb.timeKey = info.key
    cb.text:SetText(info.label)

    if i == 1 then
        cb:SetPoint("TOPLEFT", timeAll, "BOTTOMLEFT", 0, 0)
    else
        cb:SetPoint("TOPLEFT", timeChecks[i-1], "BOTTOMLEFT", 0, 0)
    end

    StyleCheckButton(cb)
    timeChecks[i] = cb
end

    ------------------------------------------------
    -- Collected filter (new UI)
    ------------------------------------------------
    local collectedLabel = drop:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    collectedLabel:SetPoint("TOPLEFT", timeChecks[#timeChecks] or timeAll, "BOTTOMLEFT", 0, -6)

    collectedLabel:SetText("Collected status")

    local collectedYes = CreateFrame("CheckButton", nil, drop, "UICheckButtonTemplate")
    collectedYes.text:SetText("Collected")
    collectedYes:SetPoint("TOPLEFT", collectedLabel, "BOTTOMLEFT", 0, 0)
    StyleCheckButton(collectedYes)

    local collectedNo = CreateFrame("CheckButton", nil, drop, "UICheckButtonTemplate")
    collectedNo.text:SetText("Uncollected")
    collectedNo:SetPoint("TOPLEFT", collectedYes, "BOTTOMLEFT", 0, 0)
    StyleCheckButton(collectedNo)

-- Height so nothing spills off the bottom: max of left & right columns
local leftRows  = 1 + #TYPE_OPTIONS                       -- ShowAll + each type

-- Right side rows:
-- 1 = Ownership label
-- 1 = All auctions
-- 1 = My bids
-- 1 = Time left label
-- 1 = All time
-- 4 = Short, Medium, Long, Very Long
-- 1 = Collected status label
-- 1 = Collected
-- 1 = Uncollected
local rightRows = 1 + 1 + 1 + 1 + 1 + 4 + 1 + 1 + 1

local rows = math.max(leftRows, rightRows)
local rowHeight = 20
local padding   = 20
drop:SetHeight(rows * rowHeight + padding)


    ------------------------------------------------
    -- Filter logic wired into controls
    ------------------------------------------------

    local function RefreshTypeCheckboxes()
        local filters = BMAHScan.filters or {}
        local set = filters.typeSet

        local allOn = not set or not next(set)
        showAll:SetChecked(allOn)

        for _, cb in ipairs(checkboxes) do
            if allOn then
                cb:SetChecked(true)
            else
                cb:SetChecked(set and set[cb.typeCode] or false)
            end
        end
    end
local function RefreshTimeCheckboxes()
    local filters = BMAHScan.filters or {}
    local set = filters.timeSet

    -- If no explicit set, everything is "on"
    local allOn = not set or not next(set)
    timeAll:SetChecked(allOn)

    for _, cb in ipairs(timeChecks) do
        if allOn then
            cb:SetChecked(true)
        else
            cb:SetChecked(set and set[cb.timeKey] or false)
        end
    end
end
    local function RefreshCollectedCheckboxes()
        local filters = BMAHScan.filters or {}
        local showC = (filters.showCollected ~= false)
        local showU = (filters.showUncollected ~= false)

        collectedYes:SetChecked(showC)
        collectedNo:SetChecked(showU)
    end

    function BMAHScan:UpdateFilterResetIcon()
        local filters = self.filters or {}
        local hasType = (filters.typeSet ~= nil)
        local hasMy   = filters.myBidsOnly and true or false
local hasTime = (filters.timeSet ~= nil)

        local showC = (filters.showCollected ~= false)
        local showU = (filters.showUncollected ~= false)
        local hasCollected = not (showC and showU)

        local btn = self.clearFiltersButton
        if not btn then return end

        if hasType or hasMy or hasTime or hasCollected then
            btn:Show()
        else
            btn:Hide()
        end
    end

    local function ApplyTypeFiltersFromUI()
        local filters = BMAHScan.filters
        filters.typeSet = filters.typeSet or {}
        local set = filters.typeSet

        if showAll:GetChecked() then
            filters.typeSet = nil
        else
            wipe(set)
            for _, cb in ipairs(checkboxes) do
                if cb:GetChecked() then
                    set[cb.typeCode] = true
                end
            end
            if not next(set) then
                -- nothing checked -> treat as "no results"
                filters.typeSet = {}
            end
        end

        BMAHScan:UpdateTypeButtonLabel()
        BMAHScan:UpdateFilterResetIcon()
        BMAHScan:RefreshWindowFromDB(false)
    end

    showAll:SetScript("OnClick", function()
        if showAll:GetChecked() then
            for _, cb in ipairs(checkboxes) do
                cb:SetChecked(true)
            end
        end
        ApplyTypeFiltersFromUI()
    end)

    for _, cb in ipairs(checkboxes) do
        cb:SetScript("OnClick", function()
            if not cb:GetChecked() then
                showAll:SetChecked(false)
            end
            ApplyTypeFiltersFromUI()
        end)
    end

    -- My bids radios
    local function UpdateMyBidRadios()
        if BMAHScan.filters.myBidsOnly then
            myRadio:SetChecked(true)
            allRadio:SetChecked(false)
        else
            myRadio:SetChecked(false)
            allRadio:SetChecked(true)
        end
    end

    allRadio:SetScript("OnClick", function()
        BMAHScan.filters.myBidsOnly = false
        UpdateMyBidRadios()
        BMAHScan:UpdateFilterResetIcon()
        BMAHScan:RefreshWindowFromDB(false)
    end)

    myRadio:SetScript("OnClick", function()
        BMAHScan.filters.myBidsOnly = true
        UpdateMyBidRadios()
        BMAHScan:UpdateFilterResetIcon()
        BMAHScan:RefreshWindowFromDB(false)
    end)

    UpdateMyBidRadios()

-- Time checkboxes
local function ApplyTimeFiltersFromUI()
    local filters = BMAHScan.filters
    filters.timeSet = filters.timeSet or {}
    local set = filters.timeSet

    if timeAll:GetChecked() then
        -- No specific filter: treat as "all times"
        filters.timeSet = nil
    else
        wipe(set)
        for _, cb in ipairs(timeChecks) do
            if cb:GetChecked() then
                set[cb.timeKey] = true
            end
        end
        if not next(set) then
            -- If user unchecks everything, fall back to "all"
            filters.timeSet = nil
        end
    end

    BMAHScan:UpdateFilterResetIcon()
    BMAHScan:RefreshWindowFromDB(false)
end

timeAll:SetScript("OnClick", function()
    if timeAll:GetChecked() then
        for _, cb in ipairs(timeChecks) do
            cb:SetChecked(true)
        end
    end
    ApplyTimeFiltersFromUI()
end)

for _, cb in ipairs(timeChecks) do
    cb:SetScript("OnClick", function(self)
        if not self:GetChecked() then
            timeAll:SetChecked(false)
        end
        ApplyTimeFiltersFromUI()
    end)
end

-- initial sync from current filters
RefreshTimeCheckboxes()


    -- Collected filter (new logic)
    local function ApplyCollectedFiltersFromUI()
        local filters = BMAHScan.filters
        filters.showCollected   = collectedYes:GetChecked()
        filters.showUncollected = collectedNo:GetChecked()

        BMAHScan:UpdateFilterResetIcon()
        BMAHScan:RefreshWindowFromDB(false)
    end

    collectedYes:SetScript("OnClick", ApplyCollectedFiltersFromUI)
    collectedNo:SetScript("OnClick", ApplyCollectedFiltersFromUI)

    RefreshCollectedCheckboxes()

    -- Clear filters button click
clearBtn:SetScript("OnClick", function()
    local filters = BMAHScan.filters
    filters.typeSet         = nil
    filters.myBidsOnly      = false
    filters.timeSet         = nil
    filters.showCollected   = true
    filters.showUncollected = true

    showAll:SetChecked(true)
    for _, cb in ipairs(checkboxes) do
        cb:SetChecked(true)
    end

    UpdateMyBidRadios()
    RefreshTimeCheckboxes()
    -- if you also have a RefreshCollectedCheckboxes() from earlier, call it here:
    -- RefreshCollectedCheckboxes()

    BMAHScan:UpdateTypeButtonLabel()
    BMAHScan:UpdateFilterResetIcon()
    BMAHScan:RefreshWindowFromDB(false)
end)


    -- Toggle dropdown visibility
    typeBtn:SetScript("OnClick", function()
        if drop:IsShown() then
            drop:Hide()
        else
            RefreshTypeCheckboxes()
            UpdateMyBidRadios()
            RefreshTimeCheckboxes()
            RefreshCollectedCheckboxes()
            drop:Show()
        end
    end)
    -- Auto-close dropdown ~0.5s after mouse leaves button + dropdown
    local function ScheduleDropdownAutoClose()
        if not C_Timer then return end
        C_Timer.After(0.5, function()
            if drop:IsShown() and not drop:IsMouseOver() and not typeBtn:IsMouseOver() then
                drop:Hide()
            end
        end)
    end

    typeBtn:HookScript("OnLeave", ScheduleDropdownAutoClose)
    drop:HookScript("OnLeave", ScheduleDropdownAutoClose)

    --------------------------------------------------------
    -- ScrollFrame + content (table area)
    --------------------------------------------------------

    local scrollFrame = CreateFrame("ScrollFrame", "BMAHScanScrollFrame", f, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 14, -56)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 24)

    -- strip decorative textures from the template
    local regions = { scrollFrame:GetRegions() }
    for _, region in ipairs(regions) do
        if region:IsObjectType("Texture") then
            region:Hide()
        end
    end

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(1, 1)
    scrollFrame:SetScrollChild(content)
    BMAHScan.content = content

    -- Column headers
    local headers = {}
    headers.high      = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    headers.item      = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    headers.bid       = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    headers.time      = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    headers.bids      = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    headers.type      = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    headers.collected = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")

    headers.high:SetText("My Bid")
    headers.item:SetText("Item")
    headers.bid:SetText("Bid")
    headers.time:SetText("Time Left")
    headers.bids:SetText("Bids")
    headers.type:SetText("Type")
    headers.collected:SetText("Collected")

    BMAHScan.headers = headers

    -- Header underline (kept invisible so it doesn't draw that little line)
    local sep = content:CreateTexture(nil, "ARTWORK")
    sep:SetColorTexture(1, 1, 1, 0)  -- fully transparent
    sep:SetHeight(1)
    BMAHScan.headerSep = sep

    -- "no results" text
    local empty = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    empty:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT_PAD, -HEADER_HEIGHT - 10)
    empty:SetJustifyH("LEFT")
    empty:SetText("No auctions to display.")
    empty:Hide()
    BMAHScan.emptyText = empty

    -- React on resize to reflow columns
    f:SetScript("OnSizeChanged", function()
        BMAHScan:UpdateColumnLayout()
    end)

    f.scrollFrame = scrollFrame
    f.content = content

    BMAHScan.window = f
    BMAHScan:UpdateColumnLayout()
    BMAHScan:UpdateFilterResetIcon()

    -- Live-update realm header "XhYmZs ago" once per second
    f._bmahTimeAccumulator = 0
    f:SetScript("OnUpdate", function(self, elapsed)
        self._bmahTimeAccumulator = (self._bmahTimeAccumulator or 0) + elapsed
        if self._bmahTimeAccumulator < 1 then
            return
        end
        self._bmahTimeAccumulator = 0

        if not BMAHScan.rows then return end

        for _, row in ipairs(BMAHScan.rows) do
            if row.isRealmHeader and row.headerData and row.cells and row.cells.item then
                local d = row.headerData

                local namePart
                if d.scannerName then
                    local coloredName = ColorizeNameByClass(d.scannerName, d.scannerClass)
                    namePart = string.format("%s - %s", coloredName, d.realmName)
                else
                    namePart = d.realmName
                end

                local timeAgo = FormatTimeAgoColored(d.lastUpdated)
                local txt = string.format("%s\n(%s)", namePart, timeAgo)
                row.cells.item:SetText(txt)
            end
        end
    end)
end


------------------------------------------------------------
-- Build rows from saved data (all realms, with filters)
------------------------------------------------------------

function BMAHScan:BuildDisplayDataFromDB()
    local data = {}
    if not BMAHScanDB then
        return data
    end

    local filters = self.filters or {}

    -- Build realm list with lastUpdated for sorting
    local realms = {}
    for realmName, realmData in pairs(BMAHScanDB) do
        if realmName ~= "_layout" then
            local lu = (realmData and realmData.lastUpdated) or 0
            table.insert(realms, { name = realmName, lastUpdated = lu })
        end
    end

    -- newest first
    table.sort(realms, function(a, b)
        if a.lastUpdated == b.lastUpdated then
            return a.name < b.name
        end
        return a.lastUpdated > b.lastUpdated
    end)

    for _, r in ipairs(realms) do
        local realmName = r.name
        local realmData = BMAHScanDB[realmName]
        if realmData and realmData.items then
            local headerAdded = false

            for _, item in ipairs(realmData.items) do
                local pass = true

                -- type filter
                local set = filters.typeSet
                if set and next(set) then
                    if not set[item.itemCategory] then
                        pass = false
                    end
                end

                -- my bids only filter
                if pass and filters.myBidsOnly then
                    if not item.highBid then
                        pass = false
                    end
                end

                -- time-left filter
                -- time-left filter (multi-select)
local timeSet = filters.timeSet
if pass and timeSet and next(timeSet) then
    local code = item.timeCode or 0
    if not timeSet[code] then
        pass = false
    end
end


                -- collected filter (new)
                if pass then
                    local col = item.collected
                    local showC = (filters.showCollected ~= false)
                    local showU = (filters.showUncollected ~= false)

                    if col == true and not showC then
                        pass = false
                    elseif col == false and not showU then
                        pass = false
                    end
                end

                if pass then
                    if not headerAdded then
                        table.insert(data, {
                            isRealmHeader = true,
                            realmName     = realmName,
                            lastUpdated   = realmData.lastUpdated,
                            scannerName   = realmData.scannerName,
                            scannerClass  = realmData.scannerClass,
                        })
                        headerAdded = true
                    end

                    table.insert(data, {
                        isRealmHeader = false,
                        realmName     = realmName,
                        itemText      = item.itemText,
                        bidText       = item.bidText,
                        timeText      = item.timeText,
                        numBids       = item.numBids,
                        highBid       = item.highBid,
                        typeLabel     = GetTypeLabel(item.itemCategory),
                        iconTexture   = item.iconTexture,
                        itemLink      = item.itemLink,
                        collected     = item.collected,
                    })
                end
            end
        end
    end

    return data
end

------------------------------------------------------------
-- Table rendering (icons in item column, tooltip on icon only)
------------------------------------------------------------

function BMAHScan:UpdateTable(displayData)
    CreateWindow()

    if self.emptyText then
        self.emptyText:Hide()
    end

    self.rows = self.rows or {}

    for _, row in ipairs(self.rows) do
        row:Hide()
    end

    if not displayData or #displayData == 0 then
        if self.emptyText then
            self.emptyText:SetText("No auctions match the current filters.")
            self.emptyText:Show()
        end
        self.content:SetHeight(HEADER_HEIGHT + 20)
        self.window:Show()
        return
    end

    local content = self.content
    local prevRow
    local visualRowIndex = 0  -- zebra striping for data rows only (currently transparent)

    for i, entry in ipairs(displayData) do
        local row = self.rows[i]
        if not row then
            row = CreateFrame("Frame", nil, content)
            row:SetHeight(ROW_HEIGHT)

            if i == 1 then
                row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(HEADER_HEIGHT + 4))
                row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -(HEADER_HEIGHT + 4))
            else
                row:SetPoint("TOPLEFT", prevRow, "BOTTOMLEFT", 0, 0)
                row:SetPoint("TOPRIGHT", prevRow, "BOTTOMRIGHT", 0, 0)
            end

            -- background (transparent, just structural)
            local bg = row:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(0, 0, 0, 0)
            row.bg = bg

            row.cells = {}

            -- icon button (inside item column)
            local iconBtn = CreateFrame("Button", nil, row)
            iconBtn:SetSize(ROW_HEIGHT, ROW_HEIGHT)
            local iconTex = iconBtn:CreateTexture(nil, "ARTWORK")
            iconTex:SetAllPoints()
            iconBtn.icon = iconTex
            iconBtn:SetScript("OnEnter", function(self)
                if self.itemLink then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetHyperlink(self.itemLink)
                    GameTooltip:Show()
                end
            end)
            iconBtn:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)
            row.iconBtn = iconBtn

            local high = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            high:SetJustifyH("CENTER")
            row.cells.high = high

            local item = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            item:SetJustifyH("LEFT")
            item:SetWordWrap(false)
            item:SetNonSpaceWrap(false)
            row.cells.item = item

            local bid = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            bid:SetJustifyH("RIGHT")
            row.cells.bid = bid

            local time = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            time:SetJustifyH("LEFT")
            row.cells.time = time

            local bids = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            bids:SetJustifyH("CENTER")
            row.cells.bids = bids

            local typeFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            typeFS:SetJustifyH("LEFT")
            row.cells.type = typeFS

            local collectedFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            collectedFS:SetJustifyH("CENTER")
            row.cells.collected = collectedFS

            self.rows[i] = row
        else
            if i == 1 then
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(HEADER_HEIGHT + 4))
                row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -(HEADER_HEIGHT + 4))
            end
        end

        if entry.isRealmHeader then
            -- Realm header row (taller, two lines)
            row.bg:Hide()
            row.cells.high:SetText("")
            row.cells.bid:SetText("")
            row.cells.time:SetText("")
            row.cells.bids:SetText("")
            row.cells.type:SetText("")
            if row.cells.collected then
                row.cells.collected:SetText("")
            end
            if row.iconBtn then
                row.iconBtn:Hide()
                row.iconBtn.itemLink = nil
            end

            -- mark this row as a header and store its data for live updating
            row.isRealmHeader = true
            row.headerData = {
                realmName    = entry.realmName,
                lastUpdated  = entry.lastUpdated,
                scannerName  = entry.scannerName,
                scannerClass = entry.scannerClass,
            }

            -- make header row taller for two lines
            row:SetHeight(ROW_HEIGHT * 2)

            -- initial text (will be updated live by OnUpdate)
            local namePart
            if entry.scannerName then
                local coloredName = ColorizeNameByClass(entry.scannerName, entry.scannerClass)
                namePart = string.format("%s - %s", coloredName, entry.realmName)
            else
                namePart = entry.realmName
            end

            local timeAgo = FormatTimeAgoColored(entry.lastUpdated)
            local txt = string.format("%s\n(%s)", namePart, timeAgo)

            row.cells.item:SetFontObject("GameFontNormal")
            row.cells.item:SetJustifyV("TOP")
            row.cells.item:SetWordWrap(true)
            row.cells.item:SetNonSpaceWrap(true)
            row.cells.item:SetText(txt)

        else
            -- Regular auction row
            row.isRealmHeader = false
            row.headerData = nil
            row:SetHeight(ROW_HEIGHT)

            visualRowIndex = visualRowIndex + 1
            -- row.bg remains transparent; we don't toggle visibility visually

            row.cells.item:SetFontObject("GameFontHighlightSmall")
            row.cells.bid:SetFontObject("GameFontHighlightSmall")
            row.cells.time:SetFontObject("GameFontHighlightSmall")
            row.cells.bids:SetFontObject("GameFontHighlightSmall")
            row.cells.high:SetFontObject("GameFontHighlightSmall")
            row.cells.type:SetFontObject("GameFontHighlightSmall")
            if row.cells.collected then
                row.cells.collected:SetFontObject("GameFontHighlightSmall")
            end

            row.cells.item:SetWordWrap(false)
            row.cells.item:SetNonSpaceWrap(false)

            row.cells.item:SetText(entry.itemText or "")
            row.cells.bid:SetText(entry.bidText or "")
            row.cells.time:SetText(entry.timeText or "")
            row.cells.bids:SetText(entry.numBids or "")
            row.cells.type:SetText(entry.typeLabel or "")

            -- collected indicator
            local collectedText = ""
            if entry.collected == true then
                collectedText = "|cff00ff00Yes|r"
            elseif entry.collected == false then
                collectedText = "|cffff0000No|r"
            else
                collectedText = ""
            end
            if row.cells.collected then
                row.cells.collected:SetText(collectedText)
            end

            if row.iconBtn then
                if entry.iconTexture then
                    row.iconBtn.icon:SetTexture(entry.iconTexture)
                    row.iconBtn:Show()
                else
                    row.iconBtn:Hide()
                end
                row.iconBtn.itemLink = entry.itemLink
            end

            if entry.highBid then
                row.cells.high:SetText("|cff00ff00Y|r")
            else
                row.cells.high:SetText("")
            end
        end

        row:Show()
        prevRow = row
    end

    -- account for taller header rows
    local totalRowHeight = 0
    for i, entry in ipairs(displayData) do
        if entry.isRealmHeader then
            totalRowHeight = totalRowHeight + (ROW_HEIGHT * 2)
        else
            totalRowHeight = totalRowHeight + ROW_HEIGHT
        end
    end

    local totalHeight = HEADER_HEIGHT + totalRowHeight + 8
    self.content:SetHeight(totalHeight)

    self:UpdateColumnLayout()
    self.window:Show()
end

function BMAHScan:RefreshWindowFromDB(showEvenIfEmpty)
    local data = self:BuildDisplayDataFromDB()

    if data and #data > 0 then
        self:UpdateTable(data)
    else
        CreateWindow()
        if self.rows then
            for _, row in ipairs(self.rows) do
                row:Hide()
            end
        end
        if self.emptyText then
            self.emptyText:SetText("No auctions match the current filters.")
            self.emptyText:Show()
        end
        self.content:SetHeight(HEADER_HEIGHT + 20)
        self.window:Show()
        if showEvenIfEmpty then
            Print("No saved Black Market scans yet (or none match filters).")
        end
    end
end

------------------------------------------------------------
-- Scan logic (current realm) + save to DB
------------------------------------------------------------

local function ClassifyType(classID, subclassID, itemType, className, subclassName)
    -- Prefer the real enum-based classification (Retail)
    if classID and Enum and Enum.ItemClass then
        if classID == Enum.ItemClass.Weapon then
            return "WEAPON"
        elseif classID == Enum.ItemClass.Armor then
            return "ARMOR"
        elseif classID == Enum.ItemClass.Battlepet then
            return "PET"
        elseif classID == Enum.ItemClass.Miscellaneous and Enum.ItemMiscellaneousSubclass then
            if subclassID == Enum.ItemMiscellaneousSubclass.Mount then
                return "MOUNT"
            elseif subclassID == Enum.ItemMiscellaneousSubclass.Toy then
                return "TOY"
            end
        end
    end

    -- Fallback to string matching if IDs/enums not available
    local t = (subclassName or className or itemType or ""):lower()

    -- IMPORTANT: detect toys before pets so they don't get mis-flagged
    if t:find("toy") then
        return "TOY"
    end

    if t:find("mount") then
        return "MOUNT"
    end

    if t:find("battle pet") or t:find("companion pet") then
        return "PET"
    end

    if t:find("armor") then
        return "ARMOR"
    end

    if t:find("weapon") then
        return "WEAPON"
    end

    return "OTHER"
end



function BMAHScan:Scan()
    if not C_BlackMarket or not C_BlackMarket.GetNumItems then
        Print("Black Market API not available. Are you on Retail with BMAH enabled?")
        return
    end

    local numItems = C_BlackMarket.GetNumItems()
    if not numItems or numItems == 0 then
        Print("No Black Market data. Make sure the Black Market window is open.")
        return
    end

    local realmName = GetRealmName() or "UnknownRealm"
    local charName = UnitName("player")
    local _, classTag = UnitClass("player")

    local items = {}

    for i = 1, numItems do
        local name, texture, quantity, itemType, usable, level, levelType,
              sellerName, minBid, minIncrement, currBid, youHaveHighBid,
              numBids, timeLeft, link, marketID =
            C_BlackMarket.GetItemInfoByIndex(i)

        if name then
            local bidCopper = (currBid and currBid > 0) and currBid or (minBid or 0)
            local bidText = bidCopper > 0 and FormatMoney(bidCopper) or "n/a"

            local timeText = timeLeftLabels[timeLeft or 0] or ("Time " .. tostring(timeLeft or "?"))
            local qtyText = (quantity and quantity > 1) and ("x" .. quantity) or ""

            local itemText
            if qtyText ~= "" then
                itemText = string.format("%s %s", link or name, qtyText)
            else
                itemText = link or name
            end

            -- Pull proper item class info
            local classID, subclassID, className, subclassName
            if link and GetItemInfo then
                local _, _, _, _, _, cName, scName, _, _, _, _, cID, sID = GetItemInfo(link)
                classID, subclassID = cID, sID
                className, subclassName = cName, scName
            end

            local category = ClassifyType(classID, subclassID, itemType, className, subclassName)

            -- Special-case: treat Unclaimed Black Market Container as its own type
            if name == "Unclaimed Black Market Container" then
                category = "CONTAINER"
            end

            local collected = IsItemCollected(category, link)

            table.insert(items, {
                itemText     = itemText,
                bidText      = bidText,
                timeText     = timeText,
                numBids      = numBids or 0,
                highBid      = youHaveHighBid and true or false,
                timeCode     = timeLeft or 0,
                itemCategory = category,
                iconTexture  = texture,
                itemLink     = link,
                collected    = collected,
            })
        end
    end

    if #items == 0 then
        Print("No active auctions found.")
        return
    end

    BMAHScanDB[realmName] = {
        lastUpdated  = time(),
        items        = items,
        scannerName  = charName,
        scannerClass = classTag,
    }

    self:RefreshWindowFromDB(false)
    Print("Scan complete for realm: " .. realmName)
end

------------------------------------------------------------
-- Events / slash command
------------------------------------------------------------

BMAHScan:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        BMAHScanDB = BMAHScanDB or {}

        SLASH_BMAHSCAN1 = "/bmahscan"
        SlashCmdList["BMAHSCAN"] = function(msg)
            msg = msg and msg:lower() or ""

            if msg == "scan" then
                if not C_BlackMarket or not C_BlackMarket.GetNumItems then
                    Print("Black Market API not available on this client.")
                    return
                end

                if not self.bmahOpen then
                    Print("Open the Black Market AH first, then use /bmahscan scan.")
                    return
                end

                if C_BlackMarket.RequestItems and C_Timer and C_Timer.After then
                    C_BlackMarket.RequestItems()
                    C_Timer.After(0.3, function()
                        if self.bmahOpen then
                            self:Scan()
                        end
                    end)
                else
                    self:Scan()
                end
            else
                self:RefreshWindowFromDB(true)
            end
        end

        Print("Loaded. /bmahscan = open window, /bmahscan scan = rescan current realm (BMAH open).")

    elseif event == "BLACK_MARKET_OPEN" then
        self.bmahOpen = true

        if C_BlackMarket and C_BlackMarket.RequestItems and C_Timer and C_Timer.After then
            C_BlackMarket.RequestItems()
            C_Timer.After(0.3, function()
                if self.bmahOpen then
                    self:Scan()
                end
            end)
        else
            self:Scan()
        end

    elseif event == "BLACK_MARKET_CLOSE" then
        self.bmahOpen = false

    elseif event == "BLACK_MARKET_ITEM_UPDATE" then
        if self.bmahOpen and self.window and self.window:IsShown() then
            self:Scan()
        end
    end
end)

BMAHScan:RegisterEvent("ADDON_LOADED")
BMAHScan:RegisterEvent("BLACK_MARKET_OPEN")
BMAHScan:RegisterEvent("BLACK_MARKET_CLOSE")
BMAHScan:RegisterEvent("BLACK_MARKET_ITEM_UPDATE")
