--[[
    ============================================
    DeepHUB - Sell Lemons Auto Farm v4.1
    UI Library: Rayfield
    Game: Sell Lemons (BloxByte Games)
    ============================================
    v4.1 Bug Fixes:
    - Fixed Enable/Disable All buttons (direct toggle references)
    - Fixed live level update (stored label references)
    - Fixed section info auto-refresh every 15 seconds
    - Added back Auto Wake Income (separate from Auto Click Earning)
    ============================================
]]

local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local Players = game:GetService('Players')
local LocalPlayer = Players.LocalPlayer

-- ============================================================
-- FIND MY TYCOON
-- ============================================================
local function findMyTycoon()
    for _, child in ipairs(workspace:GetChildren()) do
        if child:IsA('Folder') and child.Name:match('^Tycoon%d+$') then
            local ownerVal = child:FindFirstChild('Owner')
            if ownerVal and ownerVal:IsA('ObjectValue') and ownerVal.Value == LocalPlayer then
                return child
            end
        end
    end
    return nil
end

local Tycoon = findMyTycoon()
if not Tycoon then
    Rayfield:Notify({ Title = 'Error', Content = 'Tycoon not found!', Duration = 8, Image = 'alert-triangle' })
    return
end

-- ============================================================
-- REFERENCES
-- ============================================================
local Remotes = Tycoon:WaitForChild('Remotes')
local RebirthRemote = Remotes:WaitForChild('Rebirth')
local EvolveRemote = Remotes:WaitForChild('Evolve')
local AscendRemote = Remotes:WaitForChild('Ascend')
local WakeIncomeStream = Remotes:FindFirstChild('WakeIncomeStream')

local Values = Tycoon:WaitForChild('Values')
local ValuesConfig = Values:WaitForChild('Values')
local UpgradesConfig = Values:WaitForChild('Upgrades')
local PurchasesFolder = Tycoon:WaitForChild('Purchases')

-- ============================================================
-- BUILD SECTION MAP
-- ============================================================
local SectionMap = {}
local SectionOrder = {'Lemon Stand', 'LemonDash', 'Lemon Depot', 'Lemon Trading', 'Lemon Labs', 'Lemon Robotics', 'Lemon Republic', 'LemonX', 'LemonX Ground', 'Hills', 'Staircase', 'Minigames'}

local function buildSectionMap()
    SectionMap = {}
    for _, sectionName in ipairs(SectionOrder) do
        local section = PurchasesFolder:FindFirstChild(sectionName)
        if section then
            local buttons = section:FindFirstChild('Buttons')
            if buttons then
                local items = {}
                for _, desc in ipairs(buttons:GetDescendants()) do
                    if desc:IsA('RemoteFunction') and desc.Name == 'Purchase' then
                        table.insert(items, { name = desc.Parent.Name, remote = desc })
                    end
                end
                if #items > 0 then
                    table.sort(items, function(a, b) return a.name < b.name end)
                    SectionMap[sectionName] = items
                end
            end
        end
    end
end
buildSectionMap()

-- Earner remotes
local EarnerRemotes = {}
local function refreshEarnerRemotes()
    EarnerRemotes = {}
    for _, desc in ipairs(Tycoon:GetDescendants()) do
        if desc:IsA('RemoteFunction') and desc.Name == 'Upgrade' then
            local earnerPart = desc.Parent
            if earnerPart and earnerPart:IsA('BasePart') then
                table.insert(EarnerRemotes, { name = earnerPart.Name, remote = desc, part = earnerPart })
            end
        end
    end
end
refreshEarnerRemotes()

-- Fruit & Prompts
local FruitClickDetectors = {}
local EarnerPrompts = {}
local function refreshClickables()
    FruitClickDetectors = {}
    EarnerPrompts = {}
    for _, desc in ipairs(Tycoon:GetDescendants()) do
        if desc:IsA('ClickDetector') then table.insert(FruitClickDetectors, desc) end
        if desc:IsA('ProximityPrompt') then table.insert(EarnerPrompts, desc) end
    end
end
refreshClickables()

-- ============================================================
-- HELPERS
-- ============================================================
local function log10ToActual(logVal)
    if type(logVal) == 'string' then logVal = tonumber(logVal) end
    if not logVal or logVal == 0 then return 0 end
    return 10 ^ logVal
end

local function getActualCash()
    return log10ToActual(ValuesConfig:GetAttribute('Cash'))
end

local function formatCash(num)
    if num < 1000 then return string.format('$%.1f', num) end
    local suffixes = {'', 'K', 'M', 'B', 'T', 'Qa', 'Qi', 'Sx', 'Sp', 'Oc', 'No', 'Dc'}
    local tier = math.floor(math.log10(num) / 3)
    if tier >= #suffixes then return string.format('%.2fe%d', num / (10 ^ (tier * 3)), tier * 3) end
    return string.format('%.2f%s', num / (10 ^ (tier * 3)), suffixes[tier + 1])
end

-- ============================================================
-- SECTION INFO (with cache that can be refreshed)
-- ============================================================
local SectionInfo = {}
local function refreshSectionInfo()
    SectionInfo = {}
    for sectionName, items in pairs(SectionMap) do
        local bought, unlocked, locked = 0, 0, 0
        for _, item in ipairs(items) do
            local ok, result = pcall(function() return item.remote:InvokeServer() end)
            if ok then
                if result == nil then bought = bought + 1
                else unlocked = unlocked + 1 end
            else locked = locked + 1 end
        end
        SectionInfo[sectionName] = { bought = bought, unlocked = unlocked, locked = locked, total = #items }
    end
end
refreshSectionInfo()

local function getEarnerLevel(earnerName)
    return UpgradesConfig:GetAttribute(earnerName) or 0
end

-- ============================================================
-- STATE
-- ============================================================
local State = {
    SectionAutoBuy = {},
    EarnerAutoUpgrade = {},
    AutoRebirth = false,
    AutoEvolve = false,
    AutoAscend = false,
    AutoClickFruit = false,
    AutoClickEarning = false,
    AutoWakeIncome = false,
    BuyDelay = 0.1,
    UpgradeDelay = 0.3,
    StackCount = 1,
}
for name, _ in pairs(SectionMap) do State.SectionAutoBuy[name] = false end
for _, earner in ipairs(EarnerRemotes) do State.EarnerAutoUpgrade[earner.name] = false end

-- ============================================================
-- ACTION FUNCTIONS
-- ============================================================
local function purchaseItem(remote)
    local ok, result = pcall(function() return remote:InvokeServer() end)
    return ok and result == nil
end

local function upgradeEarner(earnerName, stackCount)
    for _, earner in ipairs(EarnerRemotes) do
        if earner.name == earnerName then
            return pcall(function() earner.remote:InvokeServer(stackCount or 1) end)
        end
    end
    return false
end

local function doRebirth(free)
    return pcall(function() RebirthRemote:InvokeServer(free or false) end)
end

local function doEvolve()
    return pcall(function() EvolveRemote:InvokeServer() end)
end

local function doAscend()
    return pcall(function() AscendRemote:InvokeServer() end)
end

local function smartBuySection(sectionName)
    local items = SectionMap[sectionName]
    if not items then return 0 end
    local bought = 0
    for _, item in ipairs(items) do
        if purchaseItem(item.remote) then bought = bought + 1 end
    end
    return bought
end

-- ============================================================
-- CREATE WINDOW
-- ============================================================
local Window = Rayfield:CreateWindow({
    Name = 'DeepHUB - Sell Lemons v4.1',
    LoadingTitle = 'DeepHUB',
    LoadingSubtitle = 'Loading Auto Farm...',
    ConfigurationSaving = { Enabled = true, FolderName = 'DeepHUB_SellLemons', FileName = 'Config_v41' },
    KeySystem = false
})

-- ============================================================
-- STORE REFERENCES FOR DYNAMIC UPDATES
-- ============================================================
local SectionToggles = {}  -- Store toggle objects for Enable/Disable All
local EarnerToggles = {}   -- Store toggle objects for earner upgrades
local LiveLevelLabel = nil -- Store reference to live level paragraph content
local LiveSectionLabel = nil -- Store reference to live section paragraph content

-- ============================================================
-- STATUS TAB
-- ============================================================
local StatusTab = Window:CreateTab('Status', 'home')
StatusTab:CreateSection('Information')
StatusTab:CreateButton({ Name = 'Tycoon: ' .. Tycoon.Name, Flag = 'TycoonBtn', Callback = function() Rayfield:Notify({ Title = 'Tycoon', Content = Tycoon.Name .. ' | ' .. LocalPlayer.Name, Duration = 4, Image = 'home' }) end })

StatusTab:CreateSection('Statistics')
StatusTab:CreateButton({
    Name = 'Refresh Stats',
    Flag = 'RefreshBtn',
    Callback = function()
        refreshEarnerRemotes()
        refreshClickables()
        refreshSectionInfo()
        local earnerInfo = {}
        for _, e in ipairs(EarnerRemotes) do table.insert(earnerInfo, e.name .. ' Lv.' .. getEarnerLevel(e.name)) end
        local sectionInfo = {}
        for name, info in pairs(SectionInfo) do
            table.insert(sectionInfo, string.format('%s: %d/%d bought | %d unlocked | %d locked', name, info.bought, info.total, info.unlocked, info.locked))
        end
        Rayfield:Notify({
            Title = 'Full Stats',
            Content = string.format('Cash: %s\n\nEarners:\n%s\n\nSections:\n%s', formatCash(getActualCash()), table.concat(earnerInfo, '\n'), table.concat(sectionInfo, '\n')),
            Duration = 12, Image = 'bar-chart-2'
        })
    end
})

-- Live stats paragraph (we'll update this dynamically)
StatusTab:CreateParagraph({
    Title = 'Live Stats',
    Content = 'Loading...'
})

-- ============================================================
-- AUTO BUY TAB
-- ============================================================
local BuyTab = Window:CreateTab('Auto Buy', 'shopping-cart')
BuyTab:CreateSection('Sections - Enable for auto-buy')
BuyTab:CreateParagraph({
    Title = 'How It Works',
    Content = 'Enable a section -> script automatically buys items you can AFFORD.\nAlready purchased or locked items are skipped.\nNot random - you have full control.'
})

BuyTab:CreateSlider({
    Name = 'Buy Delay', Range = {0.05, 1}, Increment = 0.05, Suffix = ' sec', CurrentValue = 0.1,
    Flag = 'BuyDelaySlider', Callback = function(v) State.BuyDelay = v end
})

-- Store toggle references for Enable/Disable All
local sectionToggleFlags = {}

BuyTab:CreateButton({
    Name = 'Enable All Sections', Flag = 'EnableAllBtn',
    Callback = function()
        for flagName, toggleObj in pairs(SectionToggles) do
            toggleObj:Set(true)
        end
        Rayfield:Notify({ Title = 'Enabled', Content = 'All sections enabled!', Duration = 3, Image = 'check-circle' })
    end
})

BuyTab:CreateButton({
    Name = 'Disable All Sections', Flag = 'DisableAllBtn',
    Callback = function()
        for flagName, toggleObj in pairs(SectionToggles) do
            toggleObj:Set(false)
        end
        Rayfield:Notify({ Title = 'Disabled', Content = 'All sections disabled!', Duration = 3, Image = 'x-circle' })
    end
})

-- Create section toggles and store references
for _, sectionName in ipairs(SectionOrder) do
    local items = SectionMap[sectionName]
    if items then
        local flagName = 'AutoBuy_' .. sectionName:gsub('%s+', '_')
        local info = SectionInfo[sectionName]
        local displayName = info and string.format('%s | %d/%d bought | %d unlocked | %d locked', sectionName, info.bought, info.total, info.unlocked, info.locked) or string.format('%s (%d items)', sectionName, #items)

        local toggle = BuyTab:CreateToggle({
            Name = displayName, CurrentValue = false, Flag = flagName,
            Callback = function(Value) State.SectionAutoBuy[sectionName] = Value end
        })
        SectionToggles[flagName] = toggle
    end
end

-- ============================================================
-- AUTO UPGRADE TAB
-- ============================================================
local UpgradeTab = Window:CreateTab('Auto Upgrade', 'trending-up')
UpgradeTab:CreateSection('Earner Upgrades')
UpgradeTab:CreateParagraph({
    Title = 'How It Works',
    Content = 'Enable an earner -> script automatically upgrades it.\nStack count determines how many levels at once.'
})

UpgradeTab:CreateSlider({
    Name = 'Upgrade Delay', Range = {0.1, 5}, Increment = 0.1, Suffix = ' sec', CurrentValue = 0.3,
    Flag = 'UpgradeDelaySlider', Callback = function(v) State.UpgradeDelay = v end
})

UpgradeTab:CreateSlider({
    Name = 'Stack Count', Range = {1, 100}, Increment = 1, Suffix = 'x', CurrentValue = 1,
    Flag = 'StackSlider', Callback = function(v) State.StackCount = math.floor(v) end
})

UpgradeTab:CreateButton({
    Name = 'Enable All Earners', Flag = 'EnableAllUpgrades',
    Callback = function()
        for flagName, toggleObj in pairs(EarnerToggles) do
            toggleObj:Set(true)
        end
        Rayfield:Notify({ Title = 'Enabled', Content = 'All earners enabled!', Duration = 3, Image = 'check-circle' })
    end
})

UpgradeTab:CreateButton({
    Name = 'Disable All Earners', Flag = 'DisableAllUpgrades',
    Callback = function()
        for flagName, toggleObj in pairs(EarnerToggles) do
            toggleObj:Set(false)
        end
        Rayfield:Notify({ Title = 'Disabled', Content = 'All earners disabled!', Duration = 3, Image = 'x-circle' })
    end
})

-- Create earner toggles and store references
for _, earner in ipairs(EarnerRemotes) do
    local flagName = 'Upgrade_' .. earner.name:gsub('%s+', '_')
    local level = getEarnerLevel(earner.name)
    local toggle = UpgradeTab:CreateToggle({
        Name = string.format('%s | Level %d', earner.name, level), CurrentValue = false, Flag = flagName,
        Callback = function(Value) State.EarnerAutoUpgrade[earner.name] = Value end
    })
    EarnerToggles[flagName] = toggle
end

-- ============================================================
-- FEATURES TAB
-- ============================================================
local FeatureTab = Window:CreateTab('Features', 'zap')
FeatureTab:CreateSection('Auto Features')

FeatureTab:CreateToggle({ Name = 'Auto Click Fruit (Lemon Trees)', CurrentValue = false, Flag = 'AutoFruit', Callback = function(v) State.AutoClickFruit = v end })
FeatureTab:CreateToggle({ Name = 'Auto Click Earning (Earner Prompts)', CurrentValue = false, Flag = 'AutoEarning', Callback = function(v) State.AutoClickEarning = v end })
FeatureTab:CreateToggle({ Name = 'Auto Wake Income Stream', CurrentValue = false, Flag = 'AutoWake', Callback = function(v) State.AutoWakeIncome = v end })
FeatureTab:CreateToggle({ Name = 'Auto Rebirth', CurrentValue = false, Flag = 'AutoRebirth', Callback = function(v) State.AutoRebirth = v end })
FeatureTab:CreateToggle({ Name = 'Auto Evolve', CurrentValue = false, Flag = 'AutoEvolve', Callback = function(v) State.AutoEvolve = v end })
FeatureTab:CreateToggle({ Name = 'Auto Ascend', CurrentValue = false, Flag = 'AutoAscend', Callback = function(v) State.AutoAscend = v end })

FeatureTab:CreateSection('Manual Actions')
FeatureTab:CreateButton({ Name = 'Buy: Lemon Stand', Flag = 'BuyLemonStand', Callback = function() Rayfield:Notify({ Title = 'Lemon Stand', Content = 'Bought: ' .. smartBuySection('Lemon Stand'), Duration = 3, Image = 'shopping-cart' }) end })
FeatureTab:CreateButton({ Name = 'Buy: LemonDash', Flag = 'BuyLemonDash', Callback = function() Rayfield:Notify({ Title = 'LemonDash', Content = 'Bought: ' .. smartBuySection('LemonDash'), Duration = 3, Image = 'shopping-cart' }) end })
FeatureTab:CreateButton({ Name = 'Rebirth Now', Flag = 'ManualRebirth', Callback = function() local ok = doRebirth(false) Rayfield:Notify({ Title = 'Rebirth', Content = ok and 'Success!' or 'Failed.', Duration = 4, Image = ok and 'check-circle' or 'x-circle' }) end })
FeatureTab:CreateButton({ Name = 'Evolve Now', Flag = 'ManualEvolve', Callback = function() local ok = doEvolve() Rayfield:Notify({ Title = 'Evolve', Content = ok and 'Success!' or 'Failed.', Duration = 4, Image = ok and 'check-circle' or 'x-circle' }) end })
FeatureTab:CreateButton({ Name = 'Ascend Now', Flag = 'ManualAscend', Callback = function() local ok = doAscend() Rayfield:Notify({ Title = 'Ascend', Content = ok and 'Success!' or 'Failed.', Duration = 4, Image = ok and 'check-circle' or 'x-circle' }) end })

-- ============================================================
-- TELEPORT TAB
-- ============================================================
local TP = Window:CreateTab('Teleport', 'map-pin')
TP:CreateSection('Locations')
local locations = Tycoon:FindFirstChild('Locations')
if locations then
    for _, loc in ipairs(locations:GetChildren()) do
        if loc:IsA('BasePart') then
            TP:CreateButton({ Name = 'TP to ' .. loc.Name, Flag = 'TP_' .. loc.Name:gsub('%s+', '_'), Callback = function() local c = LocalPlayer.Character if c and c:FindFirstChild('HumanoidRootPart') then c.HumanoidRootPart.CFrame = CFrame.new(loc.Position + Vector3.new(0, 5, 0)) Rayfield:Notify({ Title = 'Teleported', Content = loc.Name, Duration = 2, Image = 'map-pin' }) end end })
        end
    end
end
TP:CreateButton({ Name = 'Rejoin Server', Flag = 'Rejoin', Callback = function() game:GetService('TeleportService'):TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer) end })

-- ============================================================
-- DISCORD TAB
-- ============================================================
local DiscordTab = Window:CreateTab('Discord', 'message-circle')
DiscordTab:CreateSection('DeepHUB Community')
DiscordTab:CreateParagraph({ Title = 'Join Our Discord', Content = 'Join the DeepHUB community for updates, support, and exclusive scripts!' })
DiscordTab:CreateButton({
    Name = 'Join DeepHUB Discord', Flag = 'DiscordJoinBtn',
    Callback = function()
        setclipboard('https://discord.gg/cgPpYSwvxS')
        Rayfield:Notify({ Title = 'Discord Link Copied!', Content = 'Invite link copied to clipboard.', Duration = 5, Image = 'message-circle' })
    end
})
DiscordTab:CreateParagraph({ Title = 'Discord Invite', Content = 'https://discord.gg/cgPpYSwvxS\n\nClick the button above to copy the link!' })

-- ============================================================
-- SETTINGS TAB
-- ============================================================
local SettingsTab = Window:CreateTab('Settings', 'settings')
SettingsTab:CreateSection('Menu')
SettingsTab:CreateKeybind({ Name = 'Toggle Menu', CurrentKeybind = 'RightShift', HoldToInteract = false, Flag = 'MenuKey', Callback = function() Rayfield:Toggle() end })
SettingsTab:CreateButton({ Name = 'Unload Script', Flag = 'Unload', Callback = function() Rayfield:Notify({ Title = 'Unloading...', Content = 'Goodbye!', Duration = 2, Image = 'power' }); task.wait(2); Rayfield:Destroy() end })
SettingsTab:CreateParagraph({ Title = 'DeepHUB v4.1', Content = 'Press RightShift to toggle menu.\nConfiguration auto-saved.\n\nJoin Discord: https://discord.gg/cgPpYSwvxS' })

-- ============================================================
-- LIVE UPDATE LOOP (every 5 seconds)
-- ============================================================
task.spawn(function()
    while true do
        task.wait(5)

        -- Refresh section info every 15 seconds
        if math.floor(tick()) % 15 == 0 then
            refreshSectionInfo()
            -- Update section toggle names
            for _, sectionName in ipairs(SectionOrder) do
                local flagName = 'AutoBuy_' .. sectionName:gsub('%s+', '_')
                local toggle = SectionToggles[flagName]
                if toggle and SectionInfo[sectionName] then
                    local info = SectionInfo[sectionName]
                    local newName = string.format('%s | %d/%d bought | %d unlocked | %d locked', sectionName, info.bought, info.total, info.unlocked, info.locked)
                    toggle:SetDisplayName(newName)
                end
            end
        end

        -- Update earner toggle names with current levels
        for _, earner in ipairs(EarnerRemotes) do
            local flagName = 'Upgrade_' .. earner.name:gsub('%s+', '_')
            local toggle = EarnerToggles[flagName]
            if toggle then
                local level = getEarnerLevel(earner.name)
                local newName = string.format('%s | Level %d', earner.name, level)
                toggle:SetDisplayName(newName)
            end
        end

        -- Update Live Stats paragraph
        local earnerInfo = {}
        for _, e in ipairs(EarnerRemotes) do
            table.insert(earnerInfo, string.format('%s: Lv.%d', e.name, getEarnerLevel(e.name)))
        end
        local sectionSummary = {}
        for name, info in pairs(SectionInfo) do
            table.insert(sectionSummary, string.format('%s: %d/%d', name, info.bought, info.total))
        end

        -- Try to find and update the Live Stats paragraph
        local mainFrame = Window.MainFrame
        if mainFrame then
            local elements = mainFrame:FindFirstChild('Elements')
            if elements then
                local statusPage = elements:FindFirstChild('Status')
                if statusPage then
                    for _, child in ipairs(statusPage:GetChildren()) do
                        if child:IsA('Frame') and child:FindFirstChild('Title') then
                            local title = child.Title
                            if title and title:IsA('TextLabel') and title.Text == 'Live Stats' then
                                local content = child:FindFirstChild('Content')
                                if content and content:IsA('TextLabel') then
                                    content.Text = string.format('Cash: %s\n\nEarner Levels:\n%s\n\nSection Progress:\n%s',
                                        formatCash(getActualCash()),
                                        table.concat(earnerInfo, '\n'),
                                        table.concat(sectionSummary, '\n'))
                                end
                                break
                            end
                        end
                    end
                end
            end
        end
    end
end)

-- ============================================================
-- AUTO LOOPS
-- ============================================================
task.spawn(function()
    while true do
        for sn, enabled in pairs(State.SectionAutoBuy) do
            if enabled then smartBuySection(sn); task.wait(State.BuyDelay) end
        end
        task.wait(1)
    end
end)

task.spawn(function()
    while true do
        for en, enabled in pairs(State.EarnerAutoUpgrade) do
            if enabled then upgradeEarner(en, State.StackCount); task.wait(State.UpgradeDelay) end
        end
        task.wait(0.5)
    end
end)

task.spawn(function()
    while true do
        if State.AutoClickFruit then
            refreshClickables()
            for _, cd in ipairs(FruitClickDetectors) do pcall(function() fireclickdetector(cd) end) end
        end
        task.wait(0.5)
    end
end)

task.spawn(function()
    while true do
        if State.AutoClickEarning then
            refreshEarnerRemotes()
            local char = LocalPlayer.Character
            if char and char:FindFirstChild('HumanoidRootPart') then
                local hrp = char.HumanoidRootPart
                for _, earner in ipairs(EarnerRemotes) do
                    if not State.AutoClickEarning then break end
                    hrp.CFrame = CFrame.new(earner.part.Position + Vector3.new(0, 3, 5))
                    task.wait(0.2)
                    pcall(function() fireproximityprompt(earner.part:FindFirstChildOfClass('ProximityPrompt')) end)
                    task.wait(0.3)
                end
            end
        end
        task.wait(1)
    end
end)

task.spawn(function()
    while true do
        if State.AutoWakeIncome then
            if WakeIncomeStream then
                refreshEarnerRemotes()
                for _, earner in ipairs(EarnerRemotes) do
                    pcall(function() WakeIncomeStream:InvokeServer(earner.name) end)
                end
            end
        end
        task.wait(5)
    end
end)

task.spawn(function()
    while true do
        if State.AutoRebirth then doRebirth(false); doRebirth(true) end
        task.wait(5)
    end
end)

task.spawn(function()
    while true do
        if State.AutoEvolve then doEvolve() end
        task.wait(10)
    end
end)

task.spawn(function()
    while true do
        if State.AutoAscend then doAscend() end
        task.wait(15)
    end
end)

-- ============================================================
-- NOTIFY
-- ============================================================
Rayfield:Notify({
    Title = 'DeepHUB - Sell Lemons v4.1',
    Content = string.format('Loaded! Tycoon: %s | Sections: %d | Earners: %d\nJoin Discord: https://discord.gg/cgPpYSwvxS', Tycoon.Name, #SectionMap, #EarnerRemotes),
    Duration = 8, Image = 'check-circle'
})
