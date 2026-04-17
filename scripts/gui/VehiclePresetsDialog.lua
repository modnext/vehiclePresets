--
-- VehiclePresetsDialog
--
-- Author: aaw3k
-- Copyright (C) ModNext, All Rights Reserved.
--

local modDirectory = g_currentModDirectory

VehiclePresetsDialog = {}

local VehiclePresetsDialog_mt = Class(VehiclePresetsDialog, MessageDialog)

---Register the dialog GUI
function VehiclePresetsDialog.register()
  local dialog = VehiclePresetsDialog.new()

  g_gui:loadGui(modDirectory .. "gui/VehiclePresetsDialog.xml", "VehiclePresetsDialog", dialog)
  VehiclePresetsDialog.INSTANCE = dialog
end

---Show the presets dialog
-- @param function callback called with target and presetIndex when preset is loaded
-- @param table target callback target
-- @param string xmlFilename vehicle xml filename
-- @param table configurations current configuration table
-- @param table configurationData current configuration data for custom colors
-- @param table|nil licensePlateData current license plate data
function VehiclePresetsDialog.show(callback, target, xmlFilename, configurations, configurationData, licensePlateData)
  if VehiclePresetsDialog.INSTANCE == nil then
    return
  end

  local dialog = VehiclePresetsDialog.INSTANCE

  if VehiclePresetsDialog.lastXmlFilename ~= xmlFilename then
    VehiclePresetsDialog.lastXmlFilename = xmlFilename
    VehiclePresetsDialog.lastSelectedIndex = nil
  end

  dialog.xmlFilename = xmlFilename
  dialog.currentConfigurations = configurations
  dialog.currentConfigurationData = configurationData
  dialog.currentLicensePlateData = licensePlateData
  dialog:setCallback(callback, target)
  dialog:setDisableOpenSound(true)

  g_gui:showDialog("VehiclePresetsDialog")
end

---Create a new dialog instance
function VehiclePresetsDialog.new(target, custom_mt)
  local self = VehiclePresetsDialog:superClass().new(target, custom_mt or VehiclePresetsDialog_mt)

  self.presets = {}
  self.selectedIndex = nil
  self.xmlFilename = nil
  self.currentConfigurations = nil
  self.currentConfigurationData = nil
  self.currentLicensePlateData = nil

  return self
end

---Called when the dialog opens
function VehiclePresetsDialog:onOpen()
  VehiclePresetsDialog:superClass().onOpen(self)

  self.selectedIndex = nil
  self:refreshList()
end

---Called when the dialog closes
function VehiclePresetsDialog:onClose()
  VehiclePresetsDialog:superClass().onClose(self)
end

---Set callback for when a preset is loaded
-- @param function callbackFunc callback function
-- @param table target callback target
function VehiclePresetsDialog:setCallback(callbackFunc, target)
  self.callbackFunc = callbackFunc
  self.target = target
end

---Check if a preset matches the current vehicle configuration
-- @param table preset the preset to compare
-- @return boolean true when configurations and configurationData are identical
function VehiclePresetsDialog:isPresetMatchingCurrent(preset)
  if preset == nil or self.currentConfigurations == nil then
    return false
  end

  -- compare configurations one direction from preset to current
  for configName, configIndex in pairs(preset.configurations) do
    if self.currentConfigurations[configName] ~= configIndex then
      return false
    end
  end

  -- compare configurationData for custom colors and materials
  -- skip when either side is empty since ShopConfigScreen may not populate defaults after reload
  local presetData = preset.configurationData or {}
  local currentData = self.currentConfigurationData or {}

  local hasPresetData = next(presetData) ~= nil
  local hasCurrentData = next(currentData) ~= nil

  if hasPresetData and hasCurrentData then
    for configName, data in pairs(presetData) do
      if currentData[configName] == nil then
        return false
      end

      for configIndex, entry in pairs(data) do
        local currentEntry = currentData[configName][configIndex]

        if currentEntry == nil then
          return false
        end

        -- color
        if entry.color ~= nil then
          if currentEntry.color == nil then
            return false
          end

          for i = 1, 3 do
            if math.abs((entry.color[i] or 0) - (currentEntry.color[i] or 0)) > 0.001 then
              return false
            end
          end
        elseif currentEntry.color ~= nil then
          return false
        end

        -- material
        if entry.materialTemplateName ~= currentEntry.materialTemplateName then
          return false
        end
      end
    end
  end

  -- compare licensePlateData only when the preset has saved plate data
  local presetLP = preset.licensePlateData
  local currentLP = self.currentLicensePlateData

  if presetLP ~= nil and currentLP ~= nil then
    if presetLP.variation ~= currentLP.variation then
      return false
    end

    if presetLP.colorIndex ~= currentLP.colorIndex then
      return false
    end

    if presetLP.placementIndex ~= currentLP.placementIndex then
      return false
    end

    local presetChars = presetLP.characters or {}
    local currentChars = currentLP.characters or {}

    if #presetChars ~= #currentChars then
      return false
    end

    for i = 1, #presetChars do
      if presetChars[i] ~= currentChars[i] then
        return false
      end
    end
  elseif presetLP ~= nil and currentLP == nil then
    return false
  end

  return true
end

---Refresh the preset list
-- @param integer|nil selectOverride optional index to select instead of auto-detecting current
function VehiclePresetsDialog:refreshList(selectOverride)
  self.presets = g_vehiclePresetsSystem:getPresetsForVehicle(self.xmlFilename)
  self.selectedIndex = nil

  local storedIndex = VehiclePresetsDialog.lastSelectedIndex
  local hasPresets = #self.presets > 0

  self.emptyText:setVisible(not hasPresets)
  self.presetsList:setVisible(hasPresets)
  self.presetsList:reloadData()
  self:updateButtons()

  if hasPresets then
    local selectIndex = selectOverride

    if selectIndex == nil then
      local foundCurrent = false

      for i, preset in ipairs(self.presets) do
        if self:isPresetMatchingCurrent(preset) then
          selectIndex = i
          foundCurrent = true
          break
        end
      end

      if not foundCurrent then
        selectIndex = storedIndex or 1
      end
    end

    selectIndex = math.min(selectIndex, #self.presets)

    self.presetsList:setSelectedIndex(selectIndex, nil, 1)
  end
end

-- SmoothList data source: return number of items
-- @param table list the SmoothList element
-- @param integer section section index
-- @return integer count
function VehiclePresetsDialog:getNumberOfItemsInSection(list, section)
  return #self.presets
end

-- SmoothList data source: populate cell content
-- @param table list the SmoothList element
-- @param integer section section index
-- @param integer index item index
-- @param table cell the ListItem element
function VehiclePresetsDialog:populateCellForItemInSection(list, section, index, cell)
  local preset = self.presets[index]

  if preset ~= nil then
    local nameText = cell:getDescendantByName("name")
    local priceText = cell:getDescendantByName("price")
    local currentText = cell:getDescendantByName("current")

    if nameText ~= nil then
      nameText:setText(preset.name)
    end

    if priceText ~= nil then
      local totalPrice = VehiclePresetsSystem.calculatePresetPrice(self.xmlFilename, preset.configurations)

      if totalPrice ~= nil then
        priceText:setText(g_i18n:formatMoney(totalPrice, 0, true, true))
      else
        priceText:setText("")
      end
    end

    if currentText ~= nil then
      currentText:setVisible(self:isPresetMatchingCurrent(preset))
    end
  end
end

-- SmoothList callback: selection changed
-- @param table list the SmoothList element
-- @param integer section section index
-- @param integer index item index
function VehiclePresetsDialog:onListSelectionChanged(list, section, index)
  self.selectedIndex = index
  VehiclePresetsDialog.lastSelectedIndex = index
  self:updateButtons()
end

---Update button states based on selection
function VehiclePresetsDialog:updateButtons()
  local hasSelection = self.selectedIndex ~= nil

  self.loadButton:setDisabled(not hasSelection)
  self.deleteButton:setDisabled(not hasSelection)
  self.overwriteButton:setDisabled(not hasSelection)

  local canSave = #self.presets < VehiclePresetsSystem.MAX_PRESETS_PER_VEHICLE

  self.saveButton:setDisabled(not canSave)
  self.buttonsBox:invalidateLayout()
end

---Save current configuration as a new preset
function VehiclePresetsDialog:onClickSave()
  if self.xmlFilename == nil then
    return
  end

  if #self.presets >= VehiclePresetsSystem.MAX_PRESETS_PER_VEHICLE then
    return
  end

  TextInputDialog.show(function(newName, confirmed)
    if not confirmed then
      return
    end

    local trimmed = newName ~= nil and string.trim(newName) or ""

    if trimmed == "" then
      local baseName = "Preset"

      if g_i18n:hasText("vehiclePresets_preset") then
        baseName = g_i18n:getText("vehiclePresets_preset")
      end

      local id = #self.presets + 1
      trimmed = string.format("%s %d", baseName, id)

      local isUnique = false

      while not isUnique do
        isUnique = true

        for _, preset in ipairs(self.presets) do
          if preset.name == trimmed then
            id = id + 1
            trimmed = string.format("%s %d", baseName, id)
            isUnique = false
            break
          end
        end
      end
    end

    local presetIndex = g_vehiclePresetsSystem:savePreset(
      self.xmlFilename,
      trimmed,
      self.currentConfigurations,
      self.currentConfigurationData,
      self.currentLicensePlateData
    )

    if presetIndex ~= nil then
      self:refreshList()

      -- select the newly saved preset
      if self.presetsList ~= nil and presetIndex <= #self.presets then
        self.presetsList:setSelectedIndex(presetIndex, nil, 1)
      end
    end
  end, nil, "", g_i18n:getText("vehiclePresets_presetName"), g_i18n:getText("vehiclePresets_presetName"), nil, g_i18n:getText("button_ok"), nil, g_i18n:getText("vehiclePresets_savePreset"))
end

---Load the selected preset and close dialog
function VehiclePresetsDialog:onClickLoad()
  if self.selectedIndex == nil then
    return
  end

  local preset = self.presets[self.selectedIndex]

  if preset == nil then
    return
  end

  local selectedIndex = self.selectedIndex

  self:close()

  if self.callbackFunc ~= nil then
    if self.target ~= nil then
      self.callbackFunc(self.target, selectedIndex)
    else
      self.callbackFunc(selectedIndex)
    end
  end
end

---Double click to load immediately
function VehiclePresetsDialog:onDoubleClickPreset(list, section, index, cell)
  self.selectedIndex = index
  self:onClickLoad()
end

---Delete the selected preset with confirmation
function VehiclePresetsDialog:onClickDelete()
  if self.selectedIndex == nil then
    return
  end

  local preset = self.presets[self.selectedIndex]

  if preset == nil then
    return
  end

  local confirmText = string.format(g_i18n:getText("vehiclePresets_deleteConfirm"), preset.name)
  local selectedIndex = self.selectedIndex

  YesNoDialog.show(function(confirmed)
    if confirmed then
      g_vehiclePresetsSystem:deletePreset(self.xmlFilename, selectedIndex)
      self:refreshList(selectedIndex)
    end
  end, nil, confirmText, g_i18n:getText("vehiclePresets_deletePreset"))
end

---Overwrite the selected preset with current configuration
function VehiclePresetsDialog:onClickOverwrite()
  if self.selectedIndex == nil then
    return
  end

  local preset = self.presets[self.selectedIndex]

  if preset == nil then
    return
  end

  local selectedIndex = self.selectedIndex
  local currentName = preset.name

  TextInputDialog.show(function(newName, confirmed)
    if not confirmed then
      return
    end

    local trimmed = newName ~= nil and string.trim(newName) or ""

    if trimmed == "" then
      trimmed = currentName
    end

    local confirmText = string.format(g_i18n:getText("vehiclePresets_overwriteConfirm"), trimmed)

    YesNoDialog.show(function(yesConfirmed)
      if yesConfirmed then
        g_vehiclePresetsSystem:overwritePreset(
          self.xmlFilename,
          selectedIndex,
          self.currentConfigurations,
          self.currentConfigurationData,
          self.currentLicensePlateData
        )

        if trimmed ~= currentName then
          g_vehiclePresetsSystem:renamePreset(self.xmlFilename, selectedIndex, trimmed)
        end

        self:refreshList()

        if self.presetsList ~= nil and selectedIndex <= #self.presets then
          self.presetsList:setSelectedIndex(selectedIndex, nil, 1)
        end
      end
    end, nil, confirmText, g_i18n:getText("vehiclePresets_overwrite"))
  end, nil, currentName, g_i18n:getText("vehiclePresets_presetName"), g_i18n:getText("vehiclePresets_presetName"), nil, g_i18n:getText("button_ok"), nil, g_i18n:getText("vehiclePresets_overwrite"))
end

---Close dialog without action
function VehiclePresetsDialog:onClickBack(_, _)
  self:close()

  return false
end

---Setup line decorations after GUI layout is resolved
function VehiclePresetsDialog:onGuiSetupFinished()
  VehiclePresetsDialog:superClass().onGuiSetupFinished(self)

  local lineSize = (self.contentContainer.absSize[1] - self.headerText:getTextWidth()) / 2 - 20 * g_pixelSizeScaledX

  self.topLineLeft:setSize(lineSize, nil)
  self.topLineRight:setSize(lineSize, nil)
end

---
VehiclePresetsDialog.register()
