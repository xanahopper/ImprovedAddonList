local addonName, Addon = ...
local L = LibStub("AceLocale-3.0"):GetLocale(addonName)

local uncategorizedKey = {}
local categoryCollapsed = {}
local groupCollapsed = {}
local categorySearchActive = false

local function BuildAddonHierarchy(addonInfos)
    local entries, entriesByName = {}, {}
    for _, addonInfo in ipairs(addonInfos) do
        local entry = { AddonInfo = addonInfo, Children = {} }
        table.insert(entries, entry)
        entriesByName[addonInfo.Name] = entry
    end

    for _, entry in ipairs(entries) do
        local group = entry.AddonInfo.Group
        if type(group) == "string" and strtrim(group) ~= "" then
            local parent = entriesByName[group]
            if parent ~= entry then
                entry.Parent = parent
            end
        end
    end

    local resolved = {}
    for _, entry in ipairs(entries) do
        local path, positions = {}, {}
        local current = entry
        while current and not resolved[current] do
            local cycleStart = positions[current]
            if cycleStart then
                -- Invalid metadata must not make addons unreachable or trap tree traversal.
                for index = cycleStart, #path do
                    path[index].Parent = nil
                end
                break
            end
            table.insert(path, current)
            positions[current] = #path
            current = current.Parent
        end
        for _, visited in ipairs(path) do
            resolved[visited] = true
        end
    end

    local roots = {}
    for _, entry in ipairs(entries) do
        table.insert(entry.Parent and entry.Parent.Children or roots, entry)
    end
    return roots
end

local function IsAddonNodeVisible(node)
    if not node then
        return false
    end

    local parent = node:GetParent()
    while parent do
        if parent:IsCollapsed() then
            return false
        end
        parent = parent:GetParent()
    end
    return true
end

-- 插件列表项启用状态按钮函数集
ImprovedAddonListItemEnableStatusButtonMixin = {}

-- 插件列表项启用状态按钮：鼠标划入 
function ImprovedAddonListItemEnableStatusButtonMixin:OnEnter()
    GameTooltip:SetOwner(self)
    GameTooltip:AddLine(L["enable_switch"], 1, 1, 1)
    GameTooltip:Show()
end

-- 插件列表项启用状态按钮：鼠标移出
function ImprovedAddonListItemEnableStatusButtonMixin:OnLeave()
    GameTooltip:Hide()
end

-- 插件列表项启用状态按钮：鼠标点击
function ImprovedAddonListItemEnableStatusButtonMixin:OnClick()
    local addonInfo = self:GetParent():GetAddonInfo()
    if addonInfo.Enabled then
        Addon:DisableAddon(addonInfo.Name)
    else
        Addon:EnableAddon(addonInfo.Name)
    end
    Addon:RefreshAddonInfo(addonInfo.Name)
end

-- 插件列表项锁定状态按钮函数集
ImprovedAddonListItemLockStatusButtonMixin = {}

-- 插件列表项锁定状态按钮：鼠标划入 
function ImprovedAddonListItemLockStatusButtonMixin:OnEnter()
    GameTooltip:SetOwner(self)
    GameTooltip:AddLine(L["lock_tips"], 1, 1, 1)
    GameTooltip:Show()
end

-- 插件列表项锁定状态按钮：鼠标移出
function ImprovedAddonListItemLockStatusButtonMixin:OnLeave()
    GameTooltip:Hide()
end

-- 插件分组组函数集
ImprovedAddonListAddonCategoryMixin = {}

-- 插件分组：更新
function ImprovedAddonListAddonCategoryMixin:Update()
    local node = self:GetElementData()
    local categoryInfo = node:GetData().CategoryInfo
    self.Label:SetText(categoryInfo.Name)

    self:SetCollapsed(node:IsCollapsed())
end

-- 插件分组：获取分组信息
function ImprovedAddonListAddonCategoryMixin:GetCategoryInfo()
    return self:GetElementData():GetData().CategoryInfo
end

-- 插件分组：点击事件，切换折叠状态
function ImprovedAddonListAddonCategoryMixin:OnClick()
    local node = self:GetElementData()
    node:ToggleCollapsed()
    if not categorySearchActive then
        categoryCollapsed[self:GetCategoryInfo().Key] = node:IsCollapsed() or nil
    end
    self:SetCollapsed(node:IsCollapsed())
    Addon:ClearHiddenAddonSelection()
end

-- 插件分组：设置折叠状态
function ImprovedAddonListAddonCategoryMixin:SetCollapsed(collapsed)
    local atlas = collapsed and "Professions-recipe-header-expand" or "Professions-recipe-header-collapse"
    self.CollapseIcon:SetAtlas(atlas, TextureKitConstants.UseAtlasSize)
	self.CollapseIconAlphaAdd:SetAtlas(atlas, TextureKitConstants.UseAtlasSize)
end

ImprovedAddonListAddonGroupCollapseButtonMixin = {}

function ImprovedAddonListAddonGroupCollapseButtonMixin:Update()
    local node = self:GetParent():GetElementData()
    self:SetShown(#node:GetNodes() > 0)
    local atlas = node:IsCollapsed() and "Professions-recipe-header-expand" or "Professions-recipe-header-collapse"
    self.CollapseIcon:SetAtlas(atlas, TextureKitConstants.UseAtlasSize)
end

function ImprovedAddonListAddonGroupCollapseButtonMixin:OnClick()
    local node = self:GetParent():GetElementData()
    node:ToggleCollapsed()
    if not categorySearchActive then
        groupCollapsed[node:GetData().AddonInfo.Name] = node:IsCollapsed() or nil
    end
    self:Update()
    Addon:ClearHiddenAddonSelection()
end

-- 插件列表项函数集
ImprovedAddonListAddonItemMixin = {}

-- 插件列表项：更新
function ImprovedAddonListAddonItemMixin:Update()
    local addonInfo = self:GetAddonInfo()
    self.CollapseButton:Update()
    self.Label:ClearAllPoints()
    self.Label:SetPoint("LEFT", self, "LEFT", 23, 0)
    self.Label:SetPoint("RIGHT", self.EnableStatus, "LEFT", -15, 0)

    local iconText = Addon:CreateAddonIconText(addonInfo.IconText)

    -- 设置标题和加载指示器
    local loadIndicatorDisplayType = Addon:GetLoadIndicatorDisplayType()
    local label = iconText .. " "
    if loadIndicatorDisplayType == Addon.LOAD_INDICATOR_DISPLAY_INVISIBLE then
        label = label .. addonInfo.TitleWithoutColor
        self.LoadIndicator:Hide()
    elseif loadIndicatorDisplayType == Addon.LOAD_INDICATOR_DISPLAY_ONLY_COLORFUL then
        label = label .. addonInfo.Title
        self.LoadIndicator:SetShown(addonInfo.TitleColorful)
    elseif loadIndicatorDisplayType == Addon.LOAD_INDICATOR_DISPLAY_ALWAYS then
        label = label .. addonInfo.Title
        self.LoadIndicator:Show()
    end

    -- 显示备注
    if addonInfo.Remark and strlenutf8(addonInfo.Remark) > 0 then
        label = iconText .. " " .. WrapTextInColor("*", DISABLED_FONT_COLOR) .. addonInfo.Remark
    end

    self.Label:SetText(label)
    local labelColor = self:GetLabelColor()
    self:SetLabelFontColor(labelColor)
    self:SetLoadIndicatorColor(labelColor)

    self:SetSelected(self:IsSelected())
    self:SyncEnableStatus()
end

function ImprovedAddonListAddonItemMixin:SetLoadIndicatorColor(color)
    self.LoadIndicator:SetVertexColor(color:GetRGB())
end

function ImprovedAddonListAddonItemMixin:SetLabelFontColor(color)
    self.Label:SetTextColor(color:GetRGB())
end

function ImprovedAddonListAddonItemMixin:GetLabelColor()
    local addonInfo = self:GetAddonInfo()

    if Addon:IsAddonShouldReload(addonInfo.Name) then
        return Addon:GetLoadIndicatorReloadColor()
    elseif addonInfo.Loaded then
        return Addon:GetLoadIndicatorLoadedColor()
    elseif addonInfo.Enabled and not addonInfo.Loaded then
        return Addon:GetLoadIndicatorUnloadedColor()
    elseif addonInfo.Enabled and not addonInfo.Loadable then
        return Addon:GetLoadIndicatorUnloadableColor()
    else
        return Addon:GetLoadIndicatorDisabledColor()
    end
end

-- 插件列表项：同步启用按钮状态
function ImprovedAddonListAddonItemMixin:SyncEnableStatus()
    local addonInfo = self:GetAddonInfo()
    local enableStatusButton = self.EnableStatus
    local lockStatusButton = self.LockStatus
    
    if addonInfo.IsLocked or not addonInfo.Unlockable then
        enableStatusButton:Hide()
        lockStatusButton:Show()

        local lockStatusTex
        if addonInfo.Unlockable then
            lockStatusTex = [[Interface\Addons\ImprovedAddonList\Media\lock.png]]
        else
            lockStatusTex = [[Interface\Addons\ImprovedAddonList\Media\cannot_unlock.png]]
        end
        lockStatusButton:SetNormalTexture(lockStatusTex)
        lockStatusButton:SetHighlightTexture(lockStatusTex, "ADD")
        lockStatusButton:GetHighlightTexture():SetAlpha(0.2)
    else
        enableStatusButton:Show()
        lockStatusButton:Hide()

        local enableStatusTex
        if addonInfo.Enabled then
            enableStatusTex = [[Interface\Addons\ImprovedAddonList\Media\enabled.png]]
        else
            enableStatusTex = [[Interface\Addons\ImprovedAddonList\Media\enable_status_border.png]]
        end
    
        enableStatusButton:SetNormalTexture(enableStatusTex)
        enableStatusButton:SetHighlightTexture(enableStatusTex, "ADD")
        enableStatusButton:GetHighlightTexture():SetAlpha(0.2)
    end
end

-- 插件列表项：鼠标划入
function ImprovedAddonListAddonItemMixin:OnEnter()
    self:SetLabelFontColor(WHITE_FONT_COLOR) 
end

-- 插件列表项：鼠标移出
function ImprovedAddonListAddonItemMixin:OnLeave()
    self:SetLabelFontColor(self:GetLabelColor())
end

-- 插件列表项：鼠标点击
function ImprovedAddonListAddonItemMixin:OnClick()
    if self:IsSelected() then 
        Addon:ShowAddonDetail(self:GetAddonInfo().Name)
        return 
    end

    Addon:GetAddonListScrollBox().SelectionBehavior:Select(self)
    PlaySound(SOUNDKIT.UI_90_BLACKSMITHING_TREEITEMCLICK)
end

function ImprovedAddonListAddonItemMixin:OnDoubleClick()
    local addonInfo = self:GetAddonInfo()
    if addonInfo.IsLocked then
        Addon:ShowError(L["lock_tips"])
        return
    end
    self.EnableStatus:Click()
end

-- 插件列表项：设置选中
function ImprovedAddonListAddonItemMixin:SetSelected(selected)
	self.SelectedOverlay:SetShown(selected)
	self.HighlightOverlay:SetShown(not selected)
end

-- 获取插件列表项对应插件信息
function ImprovedAddonListAddonItemMixin:GetAddonInfo()
    return self:GetElementData():GetData().AddonInfo
end

-- 插件列表项是否选中
function ImprovedAddonListAddonItemMixin:IsSelected()
    return Addon:GetAddonListScrollBox().SelectionBehavior:IsElementDataSelected(self:GetElementData())
end

-- 插件列表节点更新
local function AddonListTreeNodeUpdater(factory, node)
    local elementData = node:GetData()
    local function Initializer(button, node)
        button:Update()
    end
    if elementData.CategoryInfo then
        factory("ImprovedAddonListAddonCategoryTemplate", Initializer)
    elseif elementData.AddonInfo then
        factory("ImprovedAddonListAddonItemTemplate", Initializer)
    end
end

-- 选中变化
local function AddonListNodeOnSelectionChanged(_, elementData, selected)
    local addonInfo = elementData:GetData().AddonInfo
    if not addonInfo then
        return
    end

    local button = Addon:GetAddonListScrollBox():FindFrame(elementData)
    
    if button then
        button:SetSelected(selected)
    end

    -- 显示插件详情
    if selected and addonInfo.Name ~= Addon:CurrentFocusAddonName() then
        Addon:ShowAddonDetail(addonInfo.Name)
    end
end

-- 列表长度
local function ElementExtentCalculator(index, node)
    return 25
end

-- 设置按钮：鼠标划入
local function onSettingsButtonEnter(self)
    GameTooltip:SetOwner(self)
    GameTooltip:AddLine(L["settings_tips"], 1, 1, 1)
    GameTooltip:Show()
end

-- 设置按钮：鼠标移出
local function onSettingsButtonLeave(self)
    GameTooltip:Hide()
end

-- 设置按钮：鼠标点击
local function onSettingsButtonClick(self)
    Addon:ShowAddonSettings()
end

-- 覆盖插件集按钮：鼠标划入
local function onAddonsSetOpButtonEnter(self)
    GameTooltip:SetOwner(self)
    GameTooltip:AddLine(L["addon_set_op_tips"], 1, 1, 1, true)
    GameTooltip:Show()
end

-- 覆盖插件集按钮：鼠标移出
local function onAddonsSetOpButtonLeave(self)
    GameTooltip:Hide()
end

-- 覆盖插件集按钮：鼠标点击
local function onAddonsSetOpButtonClick(self)
    local addons = {}
    local addonInfos = Addon:GetAddonInfos()
    for _, addonInfo in ipairs(addonInfos) do
        if not Addon:IsAddonManager(addonInfo.Name) and addonInfo.Enabled then
            tinsert(addons, addonInfo.Name)
        end
    end

    local choiceInfo = {
        Addons = addons
    }
    Addon:ShowAddonSetChoiceDialog(self, choiceInfo)
end

-- 启用全部按钮：鼠标划入
local function onEnableAllButtonEnter(self)
    GameTooltip:SetOwner(self)
    GameTooltip:AddLine(L["enable_all_tips"], 1, 1, 1)
    GameTooltip:Show()
end

-- 启用全部按钮：鼠标移出
local function onEnableAllButtonLeave(self)
    GameTooltip:Hide()
end

-- 启用全部按钮：鼠标点击
local function onEnableAllButtonClick(self)
    Addon:EnableAllAddons()
    Addon:RefreshAddonListContainer()
end

-- 禁用全部按钮：鼠标划入
local function onDisableAllButtonEnter(self)
    GameTooltip:SetOwner(self)
    GameTooltip:AddLine(L["disable_all_tips"], 1, 1, 1)
    GameTooltip:Show()
end

-- 禁用全部按钮：鼠标移出
local function onDisableAllButtonLeave(self)
    GameTooltip:Hide()
end

-- 禁用全部按钮：鼠标点击
local function onDisableAllButtonClick(self)
    Addon:DisableAllAddons()
    Addon:RefreshAddonListContainer()
end

-- 重置全部按钮：鼠标划入
local function onResetButtonEnter(self)
    GameTooltip:SetOwner(self)
    GameTooltip:AddLine(L["reset_tips"], 1, 1, 1)
    GameTooltip:Show()
end

-- 重置按钮：鼠标移出
local function onResetButtonLeave(self)
    GameTooltip:Hide()
end

-- 重置按钮：鼠标点击
local function onResetButtonClick(self)
    Addon:ResetAddonList()
    Addon:RefreshAddonListContainer()
end

-- 插件列表搜索框文本变化
local function onAddonListSearchBoxTextChanged(self, userInput)
    if self.searchJob then
        self.searchJob:Cancel()
    end
    
    if userInput or (self.preText and self.preText ~= self:GetText()) then
        self.preText = self:GetText()
        self.searchJob = C_Timer.NewTimer(0.25, function()
            Addon:RefreshAddonListContainer()
        end)
    end
end

-- 插件图标设置变更：显示模式
local function OnAddonIconDisplayModeChanged(self)
    self:RefreshAddonList()
end

-- 插件加载指示器设置变更：显示模式
local function OnLoadIndicatorDisplayModeSettingChanged(self)
    self:RefreshAddonList()
end

-- 插件加载指示器设置变更：颜色
local function OnLoadIndicatorColorSettingChanged(self)
    self:RefreshAddonList()
end

-- 插件列表加载
function Addon:OnAddonListContainerLoad()
    local AddonListContainer = self:GetAddonListContainer()
    
    -- 设置按钮
    local SettingsButton = CreateFrame("Button", nil, AddonListContainer)
    AddonListContainer.SettingsButtton = SettingsButton
    local settingsButtonTexture = "Interface\\AddOns\\ImprovedAddonList\\Media\\settings.png"
    SettingsButton:SetSize(16, 16)
    SettingsButton:SetNormalTexture(settingsButtonTexture)
    SettingsButton:SetHighlightTexture(settingsButtonTexture)
    SettingsButton:GetHighlightTexture():SetAlpha(0.2)
    SettingsButton:SetPoint("TOPRIGHT", -8, -8)
    SettingsButton:SetScript("OnEnter", onSettingsButtonEnter)
    SettingsButton:SetScript("OnLeave", onSettingsButtonLeave)
    SettingsButton:SetScript("OnClick", onSettingsButtonClick)

    -- 插件集操作
    local AddonSetOpButton = CreateFrame("Button", nil, AddonListContainer)
    AddonListContainer.AddonSetOpButton = AddonSetOpButton
    local overrideAddonSetButtonTexture = "Interface\\AddOns\\ImprovedAddonList\\Media\\addon_set_op.png"
    AddonSetOpButton:SetSize(16, 16)
    AddonSetOpButton:SetNormalTexture(overrideAddonSetButtonTexture)
    AddonSetOpButton:SetHighlightTexture(overrideAddonSetButtonTexture)
    AddonSetOpButton:GetHighlightTexture():SetAlpha(0.2)
    AddonSetOpButton:SetPoint("RIGHT", SettingsButton, "LEFT", -4, 0)
    AddonSetOpButton:SetScript("OnEnter", onAddonsSetOpButtonEnter)
    AddonSetOpButton:SetScript("OnLeave", onAddonsSetOpButtonLeave)
    AddonSetOpButton:SetScript("OnClick", onAddonsSetOpButtonClick)

    -- 启用全部按钮
    local EnableAllButton = CreateFrame("Button", nil, AddonListContainer)
    AddonListContainer.EnableAllButton = EnableAllButton
    EnableAllButton:SetSize(16, 16)
    EnableAllButton:SetPoint("RIGHT", AddonSetOpButton, "LEFT", -4, 0)
    EnableAllButton:SetScript("OnEnter", onEnableAllButtonEnter)
    EnableAllButton:SetScript("OnLeave", onEnableAllButtonLeave)
    EnableAllButton:SetScript("OnClick", onEnableAllButtonClick)

    -- 禁用全部按钮
    local DisableAllButton = CreateFrame("Button", nil, AddonListContainer)
    AddonListContainer.DisableAllButton = DisableAllButton
    DisableAllButton:SetSize(16, 16)
    DisableAllButton:SetPoint("RIGHT", EnableAllButton, "LEFT", -4, 0)
    DisableAllButton:SetScript("OnEnter", onDisableAllButtonEnter)
    DisableAllButton:SetScript("OnLeave", onDisableAllButtonLeave)
    DisableAllButton:SetScript("OnClick", onDisableAllButtonClick)

    -- 重置按钮
    local ResetButton = CreateFrame("Button", nil, AddonListContainer)
    AddonListContainer.ResetButton = ResetButton
    ResetButton:SetSize(16, 16)
    ResetButton:SetPoint("RIGHT", DisableAllButton, "LEFT", -4, 0)
    ResetButton:SetScript("OnEnter", onResetButtonEnter)
    ResetButton:SetScript("OnLeave", onResetButtonLeave)
    ResetButton:SetScript("OnClick", onResetButtonClick)

    -- 插件列表搜索框
    local AddonListSearchBox = CreateFrame("EditBox", nil, AddonListContainer, "SearchBoxTemplate")
    AddonListContainer.SearchBox = AddonListSearchBox
    AddonListSearchBox:SetPoint("LEFT", 14, 0)
    AddonListSearchBox:SetPoint("TOPRIGHT", ResetButton, "TOPLEFT", -5, 0)
    AddonListSearchBox:SetPoint("BOTTOMRIGHT", ResetButton, "BOTTOMLEFT", -5, 0)
    AddonListSearchBox:HookScript("OnTextChanged", onAddonListSearchBoxTextChanged)

    -- 创建插件列表
    -- 滚动框
    local AddonListScrollBox = CreateFrame("Frame", nil, AddonListContainer, "WowScrollBoxList")
    AddonListContainer.ScrollBox = AddonListScrollBox
    AddonListScrollBox:SetPoint("TOP", AddonListSearchBox, "BOTTOM", 0, -5)
    AddonListScrollBox:SetPoint("LEFT", 5, 0)
    AddonListScrollBox:SetPoint("BOTTOMRIGHT", -20, 7)
    -- 滚动条
    local AddonListScrollBar = CreateFrame("EventFrame", nil, AddonListContainer, "MinimalScrollBar")
    AddonListContainer.ScrollBar =  AddonListScrollBar
    AddonListScrollBar:SetPoint("TOPLEFT", AddonListScrollBox, "TOPRIGHT")
    AddonListScrollBar:SetPoint("BOTTOMLEFT", AddonListScrollBox, "BOTTOMRIGHT")

    local addonListTreeView = CreateScrollBoxListTreeListView(10, 5, 5, 5, 5, 1)

    --添加选中特性
    AddonListScrollBox.SelectionBehavior = ScrollUtil.AddSelectionBehavior(AddonListScrollBox)
    AddonListScrollBox.SelectionBehavior:RegisterCallback(SelectionBehaviorMixin.Event.OnSelectionChanged, AddonListNodeOnSelectionChanged)

    addonListTreeView:SetElementFactory(AddonListTreeNodeUpdater)
    addonListTreeView:SetElementExtentCalculator(ElementExtentCalculator)
    ScrollUtil.InitScrollBoxListWithScrollBar(AddonListScrollBox, AddonListScrollBar, addonListTreeView)

    self:RegisterCallback("AddonSettings.AddonIconDisplayMode", OnAddonIconDisplayModeChanged, self)
    self:RegisterCallback("AddonSettings.LoadIndicatorDisplayMode", OnLoadIndicatorDisplayModeSettingChanged, self)
    self:RegisterCallback("AddonSettings.LoadIndicatorColor", OnLoadIndicatorColorSettingChanged, self)

    self:RefreshAddonListContainer()
end

-- 刷新插件列表选项按钮的状态
function Addon:RefreshAddonListOptionButtonsStatus()
    local AddonListContainer = self:GetAddonListContainer()
    
    local allEnabled, allDisabled, canReset, shouldReload = self:IsAllAddonsEnabled()

    -- 更新启用全部按钮
    local EnableAllButton = AddonListContainer.EnableAllButton
    local enableAllTexture = "Interface\\AddOns\\ImprovedAddonList\\Media\\" .. (allEnabled and "enable_all_checked" or "enable_all")
    EnableAllButton:SetNormalTexture(enableAllTexture)
    EnableAllButton:SetHighlightTexture(enableAllTexture)
    EnableAllButton:GetHighlightTexture():SetAlpha(0.2)
    
    -- 更新禁用全部按钮
    local DisableAllButton = AddonListContainer.DisableAllButton
    local disableAllTexture = "Interface\\AddOns\\ImprovedAddonList\\Media\\" .. (allDisabled and "disable_all_checked" or "disable_all")
    DisableAllButton:SetNormalTexture(disableAllTexture)
    DisableAllButton:SetHighlightTexture(disableAllTexture)
    DisableAllButton:GetHighlightTexture():SetAlpha(0.2)

    -- 更新重置按钮
    local ResetButton = AddonListContainer.ResetButton
    local resetButtonTexture = "Interface\\AddOns\\ImprovedAddonList\\Media\\" .. (canReset and "reset.png" or "reset_disabled.png")
    ResetButton:SetNormalTexture(resetButtonTexture)
    ResetButton:SetHighlightTexture(resetButtonTexture)
    ResetButton:GetHighlightTexture():SetAlpha(0.2)

    -- 刷新重载按钮指示器
    local reloadUIIndicator = self:GetReloadUIIndicator()
    local uiShouldReload = shouldReload or false
    reloadUIIndicator:SetShown(uiShouldReload)
    reloadUIIndicator.Animation:SetPlaying(uiShouldReload)
end

-- 滚动到选中项
function Addon:ScrollToSelectedAddon()
    self:ClearHiddenAddonSelection()
    local selectedPredicate = function(elementData)
        return elementData:GetData().AddonInfo and IsAddonNodeVisible(elementData)
            and self:GetAddonListScrollBox().SelectionBehavior:IsElementDataSelected(elementData)
    end
    self:GetAddonListScrollBox():ScrollToElementDataByPredicate(selectedPredicate, ScrollBoxConstants.AlignCenter, 0, ScrollBoxConstants.NoScrollInterpolation)
end

function Addon:ClearHiddenAddonSelection()
    local focusedName = self:CurrentFocusAddonName()
    local node = focusedName and self.AddonListNodesByName and self.AddonListNodesByName[focusedName]
    if focusedName and not IsAddonNodeVisible(node) then
        self:GetAddonListScrollBox().SelectionBehavior:ClearSelections()
        self.FocusAddonInfo = nil
        self:GetAddonDetailContainer():Hide()
    end
end

-- 更新插件列表
function Addon:RefreshAddonListContainer()
    self:RefreshAddonList()
    self:ScrollToSelectedAddon()

    self:RefreshAddonDetailContainer()
    self:RefreshAddonListOptionButtonsStatus()
    self:RefreshAddonSetContainer()
end 

-- 刷新插件信息
function Addon:RefreshAddonInfo(addonName)
    self:UpdateAddonInfoByName(addonName)

    local forEach = function(frame, node)
        local addonInfo = node:GetData().AddonInfo
        if addonInfo and addonInfo.Name == addonName then
            frame:Update()
        end
    end
    self:GetAddonListScrollBox():ForEachFrame(forEach)

    self:RefreshAddonDetailContainer()
    self:RefreshAddonListOptionButtonsStatus()
    self:RefreshAddonSetContainer()
end

-- 刷新插件列表
function Addon:RefreshAddonList()
    local currentFocusAddonName = self:CurrentFocusAddonName()
    local addonDataProvider = CreateTreeDataProvider()

    local searchText = self:GetAddonListSearchBox():GetText()
    searchText = searchText and strtrim(searchText)
    searchText = searchText and searchText:lower()

    local rootNode = addonDataProvider:GetRootNode()
    local addonInfos = self:GetAddonInfos()
    local shouldFilter = searchText and strlenutf8(searchText) > 0
    local categories, categoriesByKey = {}, {}
    local nodesByName = {}

    local function MatchesAddon(addonInfo)
        local nickName = self:GetAddonRemark(addonInfo.Name) or ""
        return addonInfo.Title:lower():find(searchText, 1, true)
            or addonInfo.Name:lower():find(searchText, 1, true)
            or nickName:lower():find(searchText, 1, true)
            or type(addonInfo.Category) == "string" and addonInfo.Category:lower():find(searchText, 1, true)
    end

    local function FilterEntry(entry, ancestorMatches)
        local matches = ancestorMatches or MatchesAddon(entry.AddonInfo)
        local visible = matches
        for _, child in ipairs(entry.Children) do
            if FilterEntry(child, matches) then
                visible = true
            end
        end
        entry.Visible = visible
        return visible
    end

    for _, entry in ipairs(BuildAddonHierarchy(addonInfos)) do
        local category = entry.AddonInfo.Category
        local hasCategory = type(category) == "string" and strtrim(category) ~= ""
        local categoryKey = hasCategory and category or uncategorizedKey
        local categoryName = hasCategory and category or L["addon_category_uncategorized"]
        local categoryMatches = not shouldFilter or categoryName:lower():find(searchText, 1, true)

        if FilterEntry(entry, categoryMatches) then
            local categoryInfo = categoriesByKey[categoryKey]
            if not categoryInfo then
                categoryInfo = { Key = categoryKey, Name = categoryName, Roots = {} }
                categoriesByKey[categoryKey] = categoryInfo
                table.insert(categories, categoryInfo)
            end
            table.insert(categoryInfo.Roots, entry)
        end
    end

    table.sort(categories, function(left, right)
        if left.Key == uncategorizedKey or right.Key == uncategorizedKey then
            return right.Key == uncategorizedKey and left.Key ~= uncategorizedKey
        end
        local leftName, rightName = left.Name:lower(), right.Name:lower()
        if leftName == rightName then
            return left.Name < right.Name
        end
        return leftName < rightName
    end)

    local function InsertEntry(parentNode, entry)
        local addonInfo = entry.AddonInfo
        local node = parentNode:Insert({ AddonInfo = addonInfo })
        nodesByName[addonInfo.Name] = node
        node:SetCollapsed(not shouldFilter and groupCollapsed[addonInfo.Name] or false)
        for _, child in ipairs(entry.Children) do
            if child.Visible then
                InsertEntry(node, child)
            end
        end
    end

    for _, categoryInfo in ipairs(categories) do
        local categoryNode = rootNode:Insert({ CategoryInfo = categoryInfo })
        categoryNode:SetCollapsed(not shouldFilter and categoryCollapsed[categoryInfo.Key] or false)
        for _, entry in ipairs(categoryInfo.Roots) do
            InsertEntry(categoryNode, entry)
        end
    end

    local scrollBox = self:GetAddonListScrollBox()
    scrollBox.SelectionBehavior:ClearSelections()
    self.AddonDataProvider = addonDataProvider
    self.AddonListNodesByName = nodesByName
    categorySearchActive = shouldFilter and true or false
    scrollBox:SetDataProvider(addonDataProvider, ScrollBoxConstants.RetainScrollPosition)

    local selectedNode = currentFocusAddonName and nodesByName[currentFocusAddonName]
    if not self.AddonListSelectionInitialized then
        for _, categoryInfo in ipairs(categories) do
            local node = nodesByName[categoryInfo.Roots[1].AddonInfo.Name]
            if IsAddonNodeVisible(node) then
                selectedNode = node
                break
            end
        end
        self.AddonListSelectionInitialized = true
    end

    if IsAddonNodeVisible(selectedNode) then
        scrollBox.SelectionBehavior:SelectElementData(selectedNode)
    else
        self.FocusAddonInfo = nil
        self:GetAddonDetailContainer():Hide()
    end
end

function Addon:GetAddonListScrollBox()
    return self:GetAddonListContainer().ScrollBox
end

function Addon:GetAddonListSearchBox()
    return self:GetAddonListContainer().SearchBox
end
