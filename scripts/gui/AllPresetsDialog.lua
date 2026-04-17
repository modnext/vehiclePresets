--
-- AllPresetsDialog
--
-- Author: aaw3k
-- Copyright (C) ModNext, All Rights Reserved.
--

local modDirectory = g_currentModDirectory

AllPresetsDialog = {}

local AllPresetsDialog_mt = Class(AllPresetsDialog, MessageDialog)

---Register the dialog GUI
function AllPresetsDialog.register()
  local dialog = AllPresetsDialog.new()

  g_gui:loadGui(modDirectory .. "gui/AllPresetsDialog.xml", "AllPresetsDialog", dialog)
  AllPresetsDialog.INSTANCE = dialog
end

---Show the all-presets browser dialog
-- @param function callback called with target xmlFilename and configurations when preset is selected
-- @param table target callback target for ShopMenu instance
function AllPresetsDialog.show(callback, target)
  if AllPresetsDialog.INSTANCE == nil then
    return
  end

  local dialog = AllPresetsDialog.INSTANCE

  dialog:setCallback(callback, target)
  dialog:setDisableOpenSound(true)

  g_gui:showDialog("AllPresetsDialog")
end

---Create a new dialog instance
function AllPresetsDialog.new(target, custom_mt)
  local self = AllPresetsDialog:superClass().new(target, custom_mt or AllPresetsDialog_mt)

  self.vehicles = {}
  self.vehicleSectionTypes = {}
  self.vehiclesBySection = {}
  self.selectedSectionIndex = nil
  self.selectedIndex = nil

  return self
end

---Called when the dialog opens
function AllPresetsDialog:onOpen()
  AllPresetsDialog:superClass().onOpen(self)

  g_vehiclePresetsSystem:sync()

  self.selectedSectionIndex = nil
  self.selectedIndex = nil
  self:refreshList()
end

---Called when the dialog closes
function AllPresetsDialog:onClose()
  AllPresetsDialog:superClass().onClose(self)
end

---Set callback for when a preset is selected
-- @param function callbackFunc callback function
-- @param table target callback target
function AllPresetsDialog:setCallback(callbackFunc, target)
  self.callbackFunc = callbackFunc
  self.target = target
end

---Refresh the preset list from VehiclePresetsSystem
function AllPresetsDialog:refreshList()
  self.vehicles = g_vehiclePresetsSystem:getVehiclesWithPresetCounts()
  self:rebuildVehicleSections()
  self.selectedSectionIndex = nil
  self.selectedIndex = nil

  local hasPresets = #self.vehicles > 0

  self.emptyText:setVisible(not hasPresets)
  self.presetsList:setVisible(hasPresets)
  self.presetsList:reloadData()
  self:updateButtons()

  if hasPresets then
    self.presetsList.selectedSectionIndex = 1
    self.presetsList:setSelectedIndex(1, nil, 1)
  end
end

---Rebuild grouped vehicle sections using the same category types as ShopCategoriesFrame
function AllPresetsDialog:rebuildVehicleSections()
  self.vehicleSectionTypes = {}
  self.vehiclesBySection = {}

  local orderedCategoryTypes = g_storeManager:getCategoryTypes() or {}
  local categoryTypesByName = {}

  for _, categoryType in ipairs(orderedCategoryTypes) do
    local categoryTypeName = categoryType.name

    self.vehiclesBySection[categoryTypeName] = {}
    categoryTypesByName[categoryTypeName] = categoryType
  end

  for _, entry in ipairs(self.vehicles) do
    local sectionName = self:getCategoryTypeNameForVehicle(entry)

    if self.vehiclesBySection[sectionName] == nil then
      self.vehiclesBySection[sectionName] = {}
    end

    table.insert(self.vehiclesBySection[sectionName], entry)
  end

  for _, categoryType in ipairs(orderedCategoryTypes) do
    local sectionVehicles = self.vehiclesBySection[categoryType.name]

    if sectionVehicles ~= nil and #sectionVehicles > 0 then
      table.insert(self.vehicleSectionTypes, categoryType)
    end
  end

  local extraSectionTypes = {}

  for sectionName, sectionVehicles in pairs(self.vehiclesBySection) do
    if #sectionVehicles > 0 and categoryTypesByName[sectionName] == nil then
      table.insert(extraSectionTypes, {
        name = sectionName,
        title = sectionName
      })
    end
  end

  table.sort(extraSectionTypes, function(a, b)
    return a.title < b.title
  end)

  for _, categoryType in ipairs(extraSectionTypes) do
    table.insert(self.vehicleSectionTypes, categoryType)
  end
end

---Get the shop category type name for a vehicle entry
-- @param table entry vehicle entry
-- @return string categoryTypeName
function AllPresetsDialog:getCategoryTypeNameForVehicle(entry)
  if entry == nil or entry.xmlFilename == nil then
    return "MISC"
  end

  local storeItem = g_storeManager:getItemByXMLFilename(entry.xmlFilename)

  if storeItem == nil then
    return "MISC"
  end

  local category = g_storeManager:getCategoryByName(storeItem.categoryName)

  if category ~= nil and category.type ~= nil then
    return category.type
  end

  if storeItem.categoryName ~= nil then
    return storeItem.categoryName
  end

  return "MISC"
end

---Get the vehicle list for a given section index
-- @param integer section section index
-- @return table vehiclesInSection
function AllPresetsDialog:getVehiclesInSection(section)
  local sectionType = self.vehicleSectionTypes[section]

  if sectionType == nil then
    return nil
  end

  return self.vehiclesBySection[sectionType.name]
end

---Get a vehicle entry from a section path
-- @param integer section section index
-- @param integer index item index inside section
-- @return table|nil entry
function AllPresetsDialog:getVehicleEntry(section, index)
  local sectionVehicles = self:getVehiclesInSection(section)

  if sectionVehicles == nil then
    return nil
  end

  return sectionVehicles[index]
end

---Get the currently selected vehicle entry
-- @return table|nil entry
function AllPresetsDialog:getSelectedVehicleEntry()
  if self.selectedSectionIndex == nil or self.selectedIndex == nil then
    return nil
  end

  return self:getVehicleEntry(self.selectedSectionIndex, self.selectedIndex)
end

-- SmoothList data source: return number of sections
-- @param table list the SmoothList element
-- @return integer count
function AllPresetsDialog:getNumberOfSections(list)
  return #self.vehicleSectionTypes
end

-- SmoothList data source: return number of items
-- @param table list the SmoothList element
-- @param integer section section index
-- @return integer count
function AllPresetsDialog:getNumberOfItemsInSection(list, section)
  local sectionVehicles = self:getVehiclesInSection(section)

  return sectionVehicles ~= nil and #sectionVehicles or 0
end

-- SmoothList data source: return title for a section header
-- @param table list the SmoothList element
-- @param integer section section index
-- @return string|nil title
function AllPresetsDialog:getTitleForSectionHeader(list, section)
  local sectionType = self.vehicleSectionTypes[section]

  if sectionType == nil then
    return nil
  end

  return sectionType.title or sectionType.name
end

-- SmoothList data source: populate cell content
-- @param table list the SmoothList element
-- @param integer section section index
-- @param integer index item index
-- @param table cell the ListItem element
function AllPresetsDialog:populateCellForItemInSection(list, section, index, cell)
  local entry = self:getVehicleEntry(section, index)
  local vehicleIcon = cell:getDescendantByName("vehicleIcon")
  local titleText = cell:getDescendantByName("presetName")
  local categoryText = cell:getDescendantByName("vehicleName")

  if entry ~= nil then
    if vehicleIcon ~= nil then
      vehicleIcon:setImageFilename(entry.imageFilename)
    end

    if titleText ~= nil then
      titleText:setText(entry.vehicleName)
    end

    if categoryText ~= nil then
      categoryText:setText(string.format("%d %s", entry.presetCount, g_i18n:getText("vehiclePresets_presets")))
    end
  else
    if titleText ~= nil then
      titleText:setText("")
    end

    if categoryText ~= nil then
      categoryText:setText("")
    end
  end
end

-- SmoothList callback: selection changed
-- @param table list the SmoothList element
-- @param integer section section index
-- @param integer index item index
function AllPresetsDialog:onListSelectionChanged(list, section, index)
  self.selectedSectionIndex = section
  self.selectedIndex = index
  self:updateButtons()
end

---Update button states based on selection
function AllPresetsDialog:updateButtons()
  local hasSelection = self:getSelectedVehicleEntry() ~= nil

  self.openButton:setDisabled(not hasSelection)
  self.buttonsBox:invalidateLayout()
end

---Open ShopConfigScreen with the selected vehicle
function AllPresetsDialog:onClickOpen()
  local entry = self:getSelectedVehicleEntry()

  if entry == nil then
    return
  end

  local xmlFilename = entry.xmlFilename

  self:close()

  if self.callbackFunc ~= nil then
    if self.target ~= nil then
      self.callbackFunc(self.target, xmlFilename)
    else
      self.callbackFunc(xmlFilename)
    end
  end
end

---Double-click to open immediately
function AllPresetsDialog:onDoubleClickPreset(list, section, index, cell)
  self.selectedSectionIndex = section
  self.selectedIndex = index
  self:onClickOpen()
end

---Close dialog without action
function AllPresetsDialog:onClickBack(_, _)
  self:close()

  return false
end

---Setup line decorations after GUI layout is resolved
function AllPresetsDialog:onGuiSetupFinished()
  AllPresetsDialog:superClass().onGuiSetupFinished(self)

  local lineSize = (self.contentContainer.absSize[1] - self.headerText:getTextWidth()) / 2 - 20 * g_pixelSizeScaledX

  self.topLineLeft:setSize(lineSize, nil)
  self.topLineRight:setSize(lineSize, nil)
end

---
AllPresetsDialog.register()
