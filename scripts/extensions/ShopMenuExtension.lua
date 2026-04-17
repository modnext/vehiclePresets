--
-- ShopMenuExtension
--
-- Author: aaw3k
-- Copyright (C) ModNext, All Rights Reserved.
--

ShopMenuExtension = {}

---Open ShopConfigScreen with the selected preset's vehicle and configurations
-- @param table self ShopMenu instance
-- @param string xmlFilename vehicle xml filename
-- @param table configurations preset configurations
function ShopMenuExtension.openPresetInShop(self, xmlFilename, configurations)
  if xmlFilename == nil then
    return
  end

  local storeItem = g_storeManager:getItemByXMLFilename(xmlFilename)

  if storeItem == nil then
    return
  end

  ShopConfigScreenExtension.openPresetsDialogNextLaunch = true

  self:showConfigurationScreen(storeItem, nil, configurations)
end

---Open the all-presets browser dialog
-- @param table self ShopMenu instance
function ShopMenuExtension.onButtonVehiclePresets(self)
  AllPresetsDialog.show(function(_, xmlFilename, configurations)
    ShopMenuExtension.openPresetInShop(self, xmlFilename, configurations)
  end, self)
end

---Lazy-create the presets buttonInfo and ensure it exists on the ShopMenu instance
local function ensurePresetsButton(self)
  if self.vehiclePresetsButtonInfo ~= nil then
    return
  end

  self.vehiclePresetsButtonInfo = {
    inputAction = InputAction.MENU_EXTRA_1,
    text = g_i18n:getText("vehiclePresets_presets"),
    callback = self:makeSelfCallback(ShopMenuExtension.onButtonVehiclePresets)
  }
end

---Hook getPageButtonInfo to inject our presets button into non-detail pages
local function getPageButtonInfoOverwrite(self, superFunc, page)
  local buttons = superFunc(self, page)

  ensurePresetsButton(self)

  -- exclude only combinations sub-page
  if page == self.pageShopItemCombinations then
    return buttons
  end

  -- check if already added
  for _, btn in ipairs(buttons) do
    if btn == self.vehiclePresetsButtonInfo then
      return buttons
    end
  end

  table.insert(buttons, self.vehiclePresetsButtonInfo)

  return buttons
end

---
ShopMenu.getPageButtonInfo = Utils.overwrittenFunction(ShopMenu.getPageButtonInfo, getPageButtonInfoOverwrite)
