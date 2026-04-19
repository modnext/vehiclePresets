--
-- VehiclePresetsSystem
--
-- Author: aaw3k
-- Copyright (C) ModNext, All Rights Reserved.
--

local modSettingsDirectory = g_currentModSettingsDirectory

VehiclePresetsSystem = {
  MAX_PRESETS_PER_VEHICLE = 10,
}

local VehiclePresetsSystem_mt = Class(VehiclePresetsSystem)

---Create a new vehicle presets system instance
function VehiclePresetsSystem.new()
  local self = setmetatable({}, VehiclePresetsSystem_mt)

  self.vehicles = {}
  self.vehicleIds = {}
  self.nextVehicleId = 1

  self.isDirty = false
  self.isResolved = false
  self.hasSyncedThisSession = false

  -- load data from xml file
  self:loadFromXMLFile()

  return self
end

---Mark presets data as changed and pending save
function VehiclePresetsSystem:markDirty()
  self.isDirty = true
end

---Extract relative storage key from an absolute xmlFilename
-- @param string xmlFilename absolute or relative xml filename
-- @return string|nil storageKey relative path preserving original case
function VehiclePresetsSystem.toStorageKey(xmlFilename)
  if xmlFilename == nil then
    return nil
  end

  local normalized = xmlFilename:gsub("\\", "/")
  local lower = string.lower(normalized)

  local pos = lower:find("fs25_")

  if pos == nil then
    pos = lower:find("pdlc/")
  end

  if pos == nil then
    pos = lower:find("data/")
  end

  if pos ~= nil then
    return normalized:sub(pos)
  end

  return normalized
end

---Ensure storage keys are resolved to current runtime paths
-- Runs resolution exactly once per session on first access
function VehiclePresetsSystem:ensureResolved()
  if self.isResolved then
    return
  end

  self.isResolved = true
  self:resolveStorageKeys()
end

---Resolve storage keys to current runtime absolute paths
-- Migrates mod-relative and old absolute keys to current xmlFilenames
function VehiclePresetsSystem:resolveStorageKeys()
  local storageKeyToXml = {}

  if g_storeManager.xmlFilenameToItem ~= nil then
    for xmlFilename, _ in pairs(g_storeManager.xmlFilenameToItem) do
      local storageKey = string.lower(VehiclePresetsSystem.toStorageKey(xmlFilename))
      storageKeyToXml[storageKey] = xmlFilename
    end
  end

  local resolvedVehicles = {}
  local resolvedIds = {}

  for key, presets in pairs(self.vehicles) do
    local runtimeKey = nil
    local storageKey = string.lower(VehiclePresetsSystem.toStorageKey(key))

    if g_storeManager:getItemByXMLFilename(key) ~= nil then
      runtimeKey = string.lower(key)
    elseif storageKeyToXml[storageKey] ~= nil then
      runtimeKey = string.lower(storageKeyToXml[storageKey])
    end

    if runtimeKey ~= nil then
      resolvedVehicles[runtimeKey] = presets
      resolvedIds[runtimeKey] = self.vehicleIds[key]

      local storeItem = g_storeManager:getItemByXMLFilename(runtimeKey)

      if storeItem ~= nil then
        for _, preset in ipairs(resolvedVehicles[runtimeKey]) do
          preset.xmlFilename = storeItem.xmlFilename
        end
      end
    else
      resolvedVehicles[key] = presets
      resolvedIds[key] = self.vehicleIds[key]
    end
  end

  for key, _ in pairs(self.vehicles) do
    if resolvedVehicles[key] == nil then
      self:markDirty()
      break
    end
  end

  self.vehicles = resolvedVehicles
  self.vehicleIds = resolvedIds
end

---Get all presets for a specific vehicle
-- @param string xmlFilename vehicle xml filename identifier
-- @return table presets list of preset entries
function VehiclePresetsSystem:getPresetsForVehicle(xmlFilename)
  self:ensureResolved()

  if xmlFilename == nil then
    return {}
  end

  local key = string.lower(tostring(xmlFilename))

  return self.vehicles[key] or {}
end

---Get a specific preset by vehicle and index
-- @param string xmlFilename vehicle xml filename identifier
-- @param integer presetIndex preset index
-- @return table|nil preset
function VehiclePresetsSystem:getPreset(xmlFilename, presetIndex)
  local presets = self:getPresetsForVehicle(xmlFilename)

  return presets[presetIndex]
end

---Get the number of presets for a vehicle
-- @param string xmlFilename vehicle xml filename identifier
-- @return integer count
function VehiclePresetsSystem:getPresetCount(xmlFilename)
  return #self:getPresetsForVehicle(xmlFilename)
end

---Calculate total price of a preset configuration including base price and config deltas
-- @param string xmlFilename vehicle xml filename
-- @param table configurations configName -> configIndex table
-- @return integer|nil totalPrice or nil if vehicle not found
function VehiclePresetsSystem.calculatePresetPrice(xmlFilename, configurations)
  local storeItem = g_storeManager:getItemByXMLFilename(xmlFilename)

  if storeItem == nil then
    return nil
  end

  local basePrice = storeItem.price or 0
  local configTotal = 0

  if configurations ~= nil and storeItem.configurations ~= nil then
    for configName, configIndex in pairs(configurations) do
      local configs = storeItem.configurations[configName]

      if configs ~= nil and configs[configIndex] ~= nil then
        configTotal = configTotal + (configs[configIndex].price or 0)
      end
    end
  end

  return basePrice + configTotal
end

---Get all presets across all vehicles as a flat list
-- Each entry has xmlFilename, vehicleName, presetIndex and preset reference
-- @return table allPresets sorted by vehicle name
function VehiclePresetsSystem:getAllVehiclesWithPresets()
  local result = {}

  for xmlFilename, presets in pairs(self.vehicles) do
    if #presets > 0 then
      local storeItem = g_storeManager:getItemByXMLFilename(xmlFilename)

      -- skip vehicles from removed mods or dlcs
      if storeItem ~= nil then
        local vehicleName = storeItem.name or xmlFilename
        local imageFilename = storeItem.imageFilename

        for i, preset in ipairs(presets) do
          table.insert(result, {
            xmlFilename = xmlFilename,
            vehicleName = vehicleName,
            imageFilename = imageFilename,
            presetIndex = i,
            presetName = preset.name,
            configurations = preset.configurations,
            configurationData = preset.configurationData
          })
        end
      end
    end
  end

  -- sort by vehicle name, then preset name
  table.sort(result, function(a, b)
    if a.vehicleName == b.vehicleName then
      return a.presetName < b.presetName
    end

    return a.vehicleName < b.vehicleName
  end)

  return result
end

---Get unique vehicles that have presets, with preset count per vehicle
-- Each entry has: xmlFilename, vehicleName, imageFilename, presetCount, vehicleId
-- @return table vehicles sorted by vehicleId descending
function VehiclePresetsSystem:getVehiclesWithPresetCounts()
  local result = {}

  for xmlFilename, presets in pairs(self.vehicles) do
    if #presets > 0 then
      local storeItem = g_storeManager:getItemByXMLFilename(xmlFilename)

      -- skip vehicles from removed mods or dlcs
      if storeItem ~= nil then
        local vehicleName = storeItem.name or xmlFilename
        local imageFilename = storeItem.imageFilename

        table.insert(result, {
          xmlFilename = xmlFilename,
          vehicleName = vehicleName,
          imageFilename = imageFilename,
          presetCount = #presets,
          vehicleId = self.vehicleIds[xmlFilename] or 0,
        })
      end
    end
  end

  table.sort(result, function(a, b)
    return a.vehicleId > b.vehicleId
  end)

  return result
end

---Save a new preset for a vehicle
-- @param string xmlFilename vehicle xml filename identifier
-- @param string name preset display name
-- @param table configurations configuration table mapping configName to configIndex
-- @param table|nil configurationData optional custom color data
-- @param table|nil licensePlateData optional license plate data
-- @return integer|nil presetIndex the new preset index, or nil if limit reached
function VehiclePresetsSystem:savePreset(xmlFilename, name, configurations, configurationData, licensePlateData)
  if xmlFilename == nil or name == nil then
    return nil
  end

  local key = string.lower(tostring(xmlFilename))

  if self.vehicles[key] == nil then
    self.vehicles[key] = {}
  end

  -- assign vehicle id on first save
  if self.vehicleIds[key] == nil then
    self.vehicleIds[key] = self.nextVehicleId
    self.nextVehicleId = self.nextVehicleId + 1
  end

  local presets = self.vehicles[key]

  if #presets >= VehiclePresetsSystem.MAX_PRESETS_PER_VEHICLE then
    return nil
  end

  local preset = {
    name = string.trim(tostring(name)),
    xmlFilename = tostring(xmlFilename),
    configurations = {},
    configurationData = {},
  }

  -- deep copy configurations
  if configurations ~= nil then
    for configName, configIndex in pairs(configurations) do
      preset.configurations[configName] = configIndex
    end
  end

  -- deep copy configurationData
  if configurationData ~= nil then
    for configName, data in pairs(configurationData) do
      preset.configurationData[configName] = {}

      for configIndex, entry in pairs(data) do
        preset.configurationData[configName][configIndex] = {}

        if entry.color ~= nil then
          preset.configurationData[configName][configIndex].color = { entry.color[1], entry.color[2], entry.color[3] }
        end

        if entry.materialTemplateName ~= nil then
          preset.configurationData[configName][configIndex].materialTemplateName = entry.materialTemplateName
        end
      end
    end
  end

  -- deep copy licensePlateData
  if licensePlateData ~= nil and licensePlateData.variation ~= nil and licensePlateData.characters ~= nil then
    preset.licensePlateData = {
      variation = licensePlateData.variation,
      colorIndex = licensePlateData.colorIndex,
      placementIndex = licensePlateData.placementIndex,
      characters = {},
    }

    for i = 1, #licensePlateData.characters do
      preset.licensePlateData.characters[i] = licensePlateData.characters[i]
    end
  end

  table.insert(presets, preset)
  self:markDirty()

  return #presets
end

---Overwrite an existing preset with new configurations
-- @param string xmlFilename vehicle xml filename identifier
-- @param integer presetIndex preset index to overwrite
-- @param table configurations new configuration table
-- @param table|nil configurationData new custom color data
-- @param table|nil licensePlateData new license plate data
function VehiclePresetsSystem:overwritePreset(xmlFilename, presetIndex, configurations, configurationData, licensePlateData)
  local preset = self:getPreset(xmlFilename, presetIndex)

  if preset == nil then
    return
  end

  -- deep copy configurations
  preset.configurations = {}

  if configurations ~= nil then
    for configName, configIndex in pairs(configurations) do
      preset.configurations[configName] = configIndex
    end
  end

  -- deep copy configurationData
  preset.configurationData = {}

  if configurationData ~= nil then
    for configName, data in pairs(configurationData) do
      preset.configurationData[configName] = {}

      for configIndex, entry in pairs(data) do
        preset.configurationData[configName][configIndex] = {}

        if entry.color ~= nil then
          preset.configurationData[configName][configIndex].color = { entry.color[1], entry.color[2], entry.color[3] }
        end

        if entry.materialTemplateName ~= nil then
          preset.configurationData[configName][configIndex].materialTemplateName = entry.materialTemplateName
        end
      end
    end
  end

  -- deep copy licensePlateData
  preset.licensePlateData = nil

  if licensePlateData ~= nil and licensePlateData.variation ~= nil and licensePlateData.characters ~= nil then
    preset.licensePlateData = {
      variation = licensePlateData.variation,
      colorIndex = licensePlateData.colorIndex,
      placementIndex = licensePlateData.placementIndex,
      characters = {},
    }

    for i = 1, #licensePlateData.characters do
      preset.licensePlateData.characters[i] = licensePlateData.characters[i]
    end
  end

  self:markDirty()
end

---Delete a preset by vehicle and index
-- @param string xmlFilename vehicle xml filename identifier
-- @param integer presetIndex preset index to delete
function VehiclePresetsSystem:deletePreset(xmlFilename, presetIndex)
  if xmlFilename == nil or presetIndex == nil then
    return
  end

  local key = string.lower(tostring(xmlFilename))
  local presets = self.vehicles[key]

  if presets == nil or presets[presetIndex] == nil then
    return
  end

  table.remove(presets, presetIndex)

  if #presets == 0 then
    self.vehicles[key] = nil
    self.vehicleIds[key] = nil
  end

  self:markDirty()
end

---Rename a preset
-- @param string xmlFilename vehicle xml filename identifier
-- @param integer presetIndex preset index
-- @param string newName new display name
function VehiclePresetsSystem:renamePreset(xmlFilename, presetIndex, newName)
  local preset = self:getPreset(xmlFilename, presetIndex)

  if preset == nil or newName == nil then
    return
  end

  local trimmedName = string.trim(tostring(newName))

  if trimmedName == "" then
    return
  end

  preset.name = trimmedName
  self:markDirty()
end

---Synchronize presets with currently loaded mods
function VehiclePresetsSystem:sync()
  if self.hasSyncedThisSession then
    return
  end

  self.hasSyncedThisSession = true
  self:ensureResolved()
  self:saveIfDirty()
end

---Load presets from xml file
function VehiclePresetsSystem:loadFromXMLFile()
  self.vehicles = {}
  self.vehicleIds = {}
  self.nextVehicleId = 1
  self.isDirty = false
  self.isResolved = false

  local xmlFile = XMLFile.loadIfExists("VehiclePresetsXML", modSettingsDirectory .. "presets.xml")

  if xmlFile == nil then
    return
  end

  -- load vehicles and nested presets
  xmlFile:iterate("presets.vehicle", function(_, vehicleKey)
    local xmlFilename = xmlFile:getString(vehicleKey .. "#xmlFilename")

    if xmlFilename == nil or xmlFilename == "" then
      return
    end

    local key = string.lower(xmlFilename)
    local vehicleId = xmlFile:getInt(vehicleKey .. "#id")

    if self.vehicles[key] == nil then
      self.vehicles[key] = {}
    end

    -- restore vehicle id
    if vehicleId ~= nil then
      self.vehicleIds[key] = vehicleId

      if vehicleId >= self.nextVehicleId then
        self.nextVehicleId = vehicleId + 1
      end
    end

    local presets = self.vehicles[key]

    -- load nested presets
    xmlFile:iterate(vehicleKey .. ".preset", function(_, presetKey)
      if #presets >= VehiclePresetsSystem.MAX_PRESETS_PER_VEHICLE then
        return
      end

      local name = xmlFile:getString(presetKey .. "#name")

      if name == nil or name == "" then
        return
      end

      local preset = {
        name = name,
        xmlFilename = xmlFilename,
        configurations = {},
        configurationData = {},
      }

      -- load configurations
      xmlFile:iterate(presetKey .. ".config", function(_, configKey)
        local configName = xmlFile:getString(configKey .. "#name")
        local configIndex = xmlFile:getInt(configKey .. "#index")

        if configName ~= nil and configIndex ~= nil then
          preset.configurations[configName] = configIndex
        end
      end)

      -- load configurationData for custom colors
      xmlFile:iterate(presetKey .. ".colorData", function(_, colorKey)
        local configName = xmlFile:getString(colorKey .. "#name")
        local configIndex = xmlFile:getInt(colorKey .. "#index")
        local r = xmlFile:getFloat(colorKey .. "#r")
        local g = xmlFile:getFloat(colorKey .. "#g")
        local b = xmlFile:getFloat(colorKey .. "#b")
        local materialTemplateName = xmlFile:getString(colorKey .. "#material")

        if configName ~= nil and configIndex ~= nil then
          if preset.configurationData[configName] == nil then
            preset.configurationData[configName] = {}
          end

          preset.configurationData[configName][configIndex] = {}

          if r ~= nil and g ~= nil and b ~= nil then
            preset.configurationData[configName][configIndex].color = { r, g, b }
          end

          if materialTemplateName ~= nil then
            preset.configurationData[configName][configIndex].materialTemplateName = materialTemplateName
          end
        end
      end)

      -- load licensePlateData
      local lpVariation = xmlFile:getInt(presetKey .. ".licensePlate#variation")
      local lpCharacters = xmlFile:getString(presetKey .. ".licensePlate#characters")
      local lpColorIndex = xmlFile:getInt(presetKey .. ".licensePlate#colorIndex")
      local lpPlacementIndex = xmlFile:getInt(presetKey .. ".licensePlate#placementIndex")

      if lpVariation ~= nil and lpCharacters ~= nil then
        preset.licensePlateData = {
          variation = lpVariation,
          colorIndex = lpColorIndex,
          placementIndex = lpPlacementIndex,
          characters = {},
        }

        for i = 1, lpCharacters:len() do
          preset.licensePlateData.characters[i] = lpCharacters:sub(i, i)
        end
      end

      table.insert(presets, preset)
    end)
  end)

  xmlFile:delete()
end

---Save presets only when data has changed
function VehiclePresetsSystem:saveIfDirty()
  if not self.isDirty then
    return
  end

  self:saveToXMLFile()
end

---Save presets to xml file
function VehiclePresetsSystem:saveToXMLFile()
  createFolder(modSettingsDirectory)

  local xmlFile = XMLFile.create("VehiclePresetsXML", modSettingsDirectory .. "presets.xml", "presets")

  if xmlFile == nil then
    Logging.warning("VehiclePresets: failed to create xml file at '%s'", modSettingsDirectory)
    return
  end

  local sortedKeys = {}

  for key, presets in pairs(self.vehicles) do
    if #presets > 0 then
      table.insert(sortedKeys, key)
    end
  end

  table.sort(sortedKeys, function(a, b)
    return (self.vehicleIds[a] or 0) < (self.vehicleIds[b] or 0)
  end)

  -- save vehicles and nested presets
  local vehicleIndex = 0

  for _, key in ipairs(sortedKeys) do
    local presets = self.vehicles[key]
    if #presets > 0 then
      local vehicleKey = string.format("presets.vehicle(%d)", vehicleIndex)

      -- save vehicle id
      local vehicleId = self.vehicleIds[key]

      if vehicleId ~= nil then
        xmlFile:setInt(vehicleKey .. "#id", vehicleId)
      end

      xmlFile:setString(vehicleKey .. "#xmlFilename", VehiclePresetsSystem.toStorageKey(presets[1].xmlFilename))

      for presetIdx, preset in ipairs(presets) do
        local presetKey = string.format("%s.preset(%d)", vehicleKey, presetIdx - 1)

        xmlFile:setString(presetKey .. "#name", preset.name)

        -- save configurations
        local configIdx = 0

        for configName, configIndex in pairs(preset.configurations) do
          local configKey = string.format("%s.config(%d)", presetKey, configIdx)

          xmlFile:setString(configKey .. "#name", configName)
          xmlFile:setInt(configKey .. "#index", configIndex)
          configIdx = configIdx + 1
        end

        -- save configurationData for custom colors
        local colorIdx = 0

        for configName, data in pairs(preset.configurationData) do
          for cfgIndex, entry in pairs(data) do
            local colorKey = string.format("%s.colorData(%d)", presetKey, colorIdx)

            xmlFile:setString(colorKey .. "#name", configName)
            xmlFile:setInt(colorKey .. "#index", cfgIndex)

            if entry.color ~= nil then
              xmlFile:setFloat(colorKey .. "#r", entry.color[1])
              xmlFile:setFloat(colorKey .. "#g", entry.color[2])
              xmlFile:setFloat(colorKey .. "#b", entry.color[3])
            end

            if entry.materialTemplateName ~= nil then
              xmlFile:setString(colorKey .. "#material", entry.materialTemplateName)
            end

            colorIdx = colorIdx + 1
          end
        end

        -- save licensePlateData
        local lpData = preset.licensePlateData

        if lpData ~= nil and lpData.variation ~= nil and lpData.characters ~= nil then
          local lpKey = presetKey .. ".licensePlate"

          xmlFile:setInt(lpKey .. "#variation", lpData.variation)
          xmlFile:setString(lpKey .. "#characters", table.concat(lpData.characters, ""))

          if lpData.colorIndex ~= nil then
            xmlFile:setInt(lpKey .. "#colorIndex", lpData.colorIndex)
          end

          if lpData.placementIndex ~= nil then
            xmlFile:setInt(lpKey .. "#placementIndex", lpData.placementIndex)
          end
        end
      end

      vehicleIndex = vehicleIndex + 1
    end
  end

  xmlFile:save()
  xmlFile:delete()
  self.isDirty = false
end

---
g_vehiclePresetsSystem = VehiclePresetsSystem.new()
