--
-- ShopConfigScreenExtension
--
-- Author: aaw3k
-- Copyright (C) ModNext, All Rights Reserved.
--

ShopConfigScreenExtension = {
  openPresetsDialogNextLaunch = false
}

local isCreated = false

---Apply a preset to ShopConfigScreen
-- @param table self ShopConfigScreen instance
-- @param integer presetIndex preset index to apply
function ShopConfigScreenExtension.applyPreset(self, presetIndex)
  if self.storeItem == nil then
    return
  end

  local preset = g_vehiclePresetsSystem:getPreset(self.storeItem.xmlFilename, presetIndex)

  if preset == nil then
    return
  end

  -- build validated preset config map
  local presetConfigs = {}

  for configName, configIndex in pairs(preset.configurations) do
    local configItems = self.storeItem.configurations[configName]

    if configItems ~= nil then
      for _, item in ipairs(configItems) do
        if item.index == configIndex then
          presetConfigs[configName] = configIndex
          break
        end
      end
    end
  end

  -- find closest matching configurationSet for preset configs
  local configSets = self.storeItem.configurationSets

  if configSets ~= nil and #configSets > 1 then
    local bestSetIndex = self.currentConfigSet
    local bestMatchCount = -1

    for i, configSet in ipairs(configSets) do
      local matchCount = 0
      local isMismatch = false

      for setConfigName, setConfigIndex in pairs(configSet.configurations) do
        if presetConfigs[setConfigName] ~= nil then
          if presetConfigs[setConfigName] == setConfigIndex then
            matchCount = matchCount + 1
          else
            isMismatch = true
            break
          end
        end
      end

      if not isMismatch and matchCount > bestMatchCount then
        bestMatchCount = matchCount
        bestSetIndex = i
      end
    end

    self.currentConfigSet = bestSetIndex

    -- apply configSet defaults first then overlay with preset
    for configName, configIndex in pairs(configSets[bestSetIndex].configurations) do
      self.configurations[configName] = configIndex
    end
  end

  -- apply preset configs
  for configName, configIndex in pairs(presetConfigs) do
    self.configurations[configName] = configIndex
  end

  -- restore subConfigurations for 2-level selections (e.g. wheel brand)
  if self.storeItem.subConfigurations ~= nil then
    for configName, configIndex in pairs(presetConfigs) do
      if self.storeItem.subConfigurations[configName] ~= nil then
        local subIndex = StoreItemUtil.getSubConfigurationIndex(self.storeItem, configName, configIndex)

        if subIndex ~= nil then
          self.subConfigurations[configName] = subIndex
        end
      end
    end
  end

  -- restore configurationData for custom colors
  self.configurationData = {}

  if preset.configurationData ~= nil then
    for configName, data in pairs(preset.configurationData) do
      if self.configurationData[configName] == nil then
        self.configurationData[configName] = {}
      end

      for configIndex, entry in pairs(data) do
        self.configurationData[configName][configIndex] = {}

        if entry.color ~= nil then
          self.configurationData[configName][configIndex].color = { entry.color[1], entry.color[2], entry.color[3] }
        end

        if entry.materialTemplateName ~= nil then
          self.configurationData[configName][configIndex].materialTemplateName = entry.materialTemplateName
        end
      end
    end
  end

  -- restore licensePlateData
  if preset.licensePlateData ~= nil and self.licensePlateData ~= nil then
    self.licensePlateData.variation = preset.licensePlateData.variation
    self.licensePlateData.colorIndex = preset.licensePlateData.colorIndex
    self.licensePlateData.placementIndex = preset.licensePlateData.placementIndex
    self.licensePlateData.customized = true

    if preset.licensePlateData.characters ~= nil then
      self.licensePlateData.characters = {}

      for i = 1, #preset.licensePlateData.characters do
        self.licensePlateData.characters[i] = preset.licensePlateData.characters[i]
      end
    end

    -- apply to preview vehicles
    for _, vehicle in ipairs(self.previewVehicles) do
      if vehicle.setLicensePlatesData ~= nil and vehicle.getHasLicensePlates ~= nil and vehicle:getHasLicensePlates() then
        vehicle:setLicensePlatesData(self.licensePlateData)
      end
    end

    -- update license plate preview graphic
    if self.updateLicensePlateGraphics ~= nil then
      self:updateLicensePlateGraphics()
    end
  end

  -- refresh display with correct currentConfigSet
  self:updateDisplay(self.storeItem, self.vehicle, self.saleItem)
end

---Open the presets dialog
-- @param table self ShopConfigScreen instance
function ShopConfigScreenExtension.onOpenPresetsDialog(self)
  if self.storeItem == nil then
    return
  end

  local licensePlateData = nil

  if self.licensePlateData ~= nil then
    for _, vehicle in ipairs(self.previewVehicles or {}) do
      if vehicle.getHasLicensePlates ~= nil and vehicle:getHasLicensePlates() then
        licensePlateData = self.licensePlateData
        break
      end
    end
  end

  VehiclePresetsDialog.show(function(_, presetIndex)
    if presetIndex ~= nil then
      ShopConfigScreenExtension.applyPreset(self, presetIndex)
    end
  end, self, self.storeItem.xmlFilename, self.configurations, self.configurationData, licensePlateData)
end

---Hook updateButtons to inject the presets button using the same pattern as FS22_ShopExtension
local function updateButtons(self, superFunc, storeItem, vehicle, saleItem)
  superFunc(self, storeItem, vehicle, saleItem)

  if not isCreated then
    self.presetsButton = self.buyButton:clone(self.buttonsPanel)

    self.presetsButton:setText(g_i18n:getText("vehiclePresets_dialogTitle"))
    self.presetsButton:applyProfile(ShopConfigScreen.GUI_PROFILE.BUTTON_BUY)
    self.presetsButton:setInputAction(InputAction.VEHICLE_PRESETS)
    self.presetsButton.onClickCallback = function()
      ShopConfigScreenExtension.onOpenPresetsDialog(self)
    end

    isCreated = true
  end

  local hasSelectableConfig = false

  if storeItem ~= nil and storeItem.configurations ~= nil then
    for _, configItems in pairs(storeItem.configurations) do
      if #configItems > 1 then
        hasSelectableConfig = true
        break
      end
    end
  end

  self.presetsButton:setVisible(hasSelectableConfig)
  self.buttonsPanel:invalidateLayout()

  -- open presets dialog if requested
  if ShopConfigScreenExtension.openPresetsDialogNextLaunch then
    ShopConfigScreenExtension.openPresetsDialogNextLaunch = false
    ShopConfigScreenExtension.onOpenPresetsDialog(self)
  end
end

---
ShopConfigScreen.updateButtons = Utils.overwrittenFunction(ShopConfigScreen.updateButtons, updateButtons)

---Register custom action in ShopConfigScreen input context
local function registerInputActionsAppended(self)
  g_inputBinding:registerActionEvent(InputAction.VEHICLE_PRESETS, self, function()
    ShopConfigScreenExtension.onOpenPresetsDialog(self)
  end, false, true, false, true)
end

---
ShopConfigScreen.registerInputActions = Utils.appendedFunction(ShopConfigScreen.registerInputActions, registerInputActionsAppended)

---Save data when preview vehicles are deleted called from onClose
local function deletePreviewVehiclesAppended(self)
  if g_vehiclePresetsSystem ~= nil then
    g_vehiclePresetsSystem:saveIfDirty()
  end
end

---
ShopConfigScreen.deletePreviewVehicles = Utils.appendedFunction(ShopConfigScreen.deletePreviewVehicles, deletePreviewVehiclesAppended)
