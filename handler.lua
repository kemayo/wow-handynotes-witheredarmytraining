local myname, ns = ...

local HandyNotes = LibStub("AceAddon-3.0"):GetAddon("HandyNotes")
local HL = LibStub("AceAddon-3.0"):NewAddon(myname, "AceEvent-3.0")
-- local L = LibStub("AceLocale-3.0"):GetLocale(myname, true)
ns.HL = HL

local next = next
local GameTooltip = GameTooltip
local WorldMapTooltip = WorldMapTooltip
local HandyNotes = HandyNotes

local function work_out_texture(atlas)
    local texture, _, _, left, right, top, bottom = GetAtlasInfo(atlas)
    return {
        icon = texture,
        tCoordLeft = left,
        tCoordRight = right,
        tCoordTop = top,
        tCoordBottom = bottom,
    }
end
local chest_texture = work_out_texture("Garr_TreasureIcon")

local get_point_info = function(point)
    if point then
        return point.label, chest_texture
    end
end
local get_point_info_by_coord = function(mapFile, coord)
    mapFile = string.gsub(mapFile, "_terrain%d+$", "")
    return get_point_info(ns.points[mapFile] and ns.points[mapFile][coord])
end

local function handle_tooltip(tooltip, point)
    if point then
        if point.label then
            tooltip:AddLine(point.label)
        end
        if point.item then
            local name, link = GetItemInfo(point.item)
            tooltip:AddLine(link and (link:gsub("[%[%]]", "")) or name)
        end
        if point.note then
            tooltip:AddLine(point.note, nil, nil, nil, true)
        end
        if point.quest then
            if IsQuestFlaggedCompleted(point.quest) then
                tooltip:AddLine(LOOT_GONE, 0, 1, 0) -- Item already looted
            else
                tooltip:AddLine(NEED, 1, 0, 0) -- Need
            end
            tooltip:AddDoubleLine("QuestID", point.quest)
        end
    else
        tooltip:SetText(UNKNOWN)
    end
    tooltip:Show()
end
local handle_tooltip_by_coord = function(tooltip, mapFile, coord)
    mapFile = string.gsub(mapFile, "_terrain%d+$", "")
    return handle_tooltip(tooltip, ns.points[mapFile] and ns.points[mapFile][coord])
end

---------------------------------------------------------
-- Plugin Handlers to HandyNotes
local HLHandler = {}
local info = {}

function HLHandler:OnEnter(mapFile, coord)
    local tooltip = self:GetParent() == WorldMapButton and WorldMapTooltip or GameTooltip
    if ( self:GetCenter() > UIParent:GetCenter() ) then -- compare X coordinate
        tooltip:SetOwner(self, "ANCHOR_LEFT")
    else
        tooltip:SetOwner(self, "ANCHOR_RIGHT")
    end
    handle_tooltip_by_coord(tooltip, mapFile, coord)
end

local function createWaypoint(button, mapFile, coord)
    if TomTom then
        local mapId = HandyNotes:GetMapFiletoMapID(mapFile)
        local x, y = HandyNotes:getXY(coord)
        TomTom:AddMFWaypoint(mapId, nil, x, y, {
            title = get_point_info_by_coord(mapFile, coord),
            persistent = nil,
            minimap = true,
            world = true
        })
    end
end

local function hideNode(button, mapFile, coord)
    ns.hidden[mapFile][coord] = true
    HL:Refresh()
end

local function closeAllDropdowns()
    CloseDropDownMenus(1)
end

do
    local currentZone, currentCoord
    local function generateMenu(button, level)
        if (not level) then return end
        wipe(info)
        if (level == 1) then
            -- Create the title of the menu
            info.isTitle      = 1
            info.text         = "HandyNotes - " .. myname:gsub("HandyNotes_", "")
            info.notCheckable = 1
            UIDropDownMenu_AddButton(info, level)
            wipe(info)

            if TomTom then
                -- Waypoint menu item
                info.text = "Create waypoint"
                info.notCheckable = 1
                info.func = createWaypoint
                info.arg1 = currentZone
                info.arg2 = currentCoord
                UIDropDownMenu_AddButton(info, level)
                wipe(info)
            end

            -- Close menu item
            info.text         = "Close"
            info.func         = closeAllDropdowns
            info.notCheckable = 1
            UIDropDownMenu_AddButton(info, level)
            wipe(info)
        end
    end
    local HL_Dropdown = CreateFrame("Frame", myname.."DropdownMenu")
    HL_Dropdown.displayMode = "MENU"
    HL_Dropdown.initialize = generateMenu

    function HLHandler:OnClick(button, down, mapFile, coord)
        if button == "RightButton" and not down then
            currentZone = string.gsub(mapFile, "_terrain%d+$", "")
            currentCoord = coord
            ToggleDropDownMenu(1, nil, HL_Dropdown, self, 0, 0)
        end
    end
end

function HLHandler:OnLeave(mapFile, coord)
    if self:GetParent() == WorldMapButton then
        WorldMapTooltip:Hide()
    else
        GameTooltip:Hide()
    end
end

do
    -- This is a custom iterator we use to iterate over every node in a given zone
    local currentLevel, currentZone
    local function iter(t, prestate)
        if not t then return nil end
        local state, value = next(t, prestate)
        while state do -- Have we reached the end of this zone?
            if value and ns:ShouldShow(value) then
                return state, nil, chest_texture, ns.db.icon_scale, ns.db.icon_alpha
            end
            state, value = next(t, state) -- Get next data
        end
        return nil, nil, nil, nil
    end
    function HLHandler:GetNodes(mapFile, minimap, level)
        currentLevel = level
        mapFile = string.gsub(mapFile, "_terrain%d+$", "")
        currentZone = mapFile
        return iter, ns.points[mapFile], nil
    end
    function ns:ShouldShow(point)
        if point.level and point.level ~= currentLevel then
            return false
        end
        if point.hide_after and IsQuestFlaggedCompleted(point.hide_after) then
            return false
        end
        if point.hide_before and not IsQuestFlaggedCompleted(point.hide_before) then
            return false
        end
        if point.quest and not ns.db.completed and IsQuestFlaggedCompleted(point.quest) then
            return false
        end
        return true
    end
end

---------------------------------------------------------
-- Addon initialization, enabling and disabling

function HL:OnInitialize()
    -- Set up our database
    self.db = LibStub("AceDB-3.0"):New(myname.."DB", ns.defaults)
    ns.db = self.db.profile
    ns.hidden = self.db.char.hidden
    -- Initialize our database with HandyNotes
    HandyNotes:RegisterPluginDB(myname:gsub("HandyNotes_", ""), HLHandler, ns.options)

    -- watch for LOOT_CLOSED
    self:RegisterEvent("LOOT_CLOSED")
end

function HL:Refresh()
    self:SendMessage("HandyNotes_NotifyUpdate", myname:gsub("HandyNotes_", ""))
end

function HL:LOOT_CLOSED()
    self:Refresh()
end
