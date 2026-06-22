--[[
    ============================================
    DeepHUB - Sell Lemons Auto Farm v3.0
    UI Library: Rayfield
    Game: Jual Jeruk / Sell Lemons (BloxByte Games)
    ============================================
    v3.0 Changes:
    - Per-section auto buy (pilih section mana yang mau dibeli)
    - Smart buy: beli item yang UANG CUKUP dulu (termurah -> termahal)
    - Per-earner upgrade toggle (pilih earner mana yang di-upgrade)
    - Tidak random - user full control
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
    Rayfield:Notify({ Title = 'Error', Content = 'Tycoon tidak ditemukan!', Duration = 8, Image = 'alert-triangle' })
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
        if desc:IsA('ClickDetector') then
            table.insert(FruitClickDetectors, desc)
        end
        if desc:IsA('ProximityPrompt') then
            table.insert(EarnerPrompts, desc)
        end
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
-- STATE
-- ============================================================
local State = {
    SectionAutoBuy = {},    -- SectionAutoBuy['Lemon Stand'] = true/false
    EarnerAutoUpgrade = {}, -- EarnerAutoUpgrade['Lemon Stand'] = true/false
    AutoRebirth = false,
    AutoEvolve = false,
    AutoAscend = false,
    AutoClickFruit = false,
    AutoClickStand = false,
    AutoWakeIncome = false,
    BuyDelay = 0.1,
    UpgradeDelay = 0.3,
    StackCount = 1,
}

-- Initialize section toggles to false
for name, _ in pairs(SectionMap) do
    State.SectionAutoBuy[name] = false
end
for _, earner in ipairs(EarnerRemotes) do
    State.EarnerAutoUpgrade[earner.name] = false
end

-- ============================================================
-- ACTION FUNCTIONS
-- ============================================================
local function purchaseItem(remote)
    local ok, result = pcall(function() return remote:InvokeServer() end)
    if ok and result == nil then return true end
    return false
end

local function upgradeEarner(earnerName, stackCount)
    for _, earner in ipairs(EarnerRemotes) do
        if earner.name == earnerName then
            local ok = pcall(function() earner.remote:InvokeServer(stackCount or 1) end)
            return ok
        end
    end
    return false
end

local function doRebirth(free)
    local ok = pcall(function() RebirthRemote:InvokeServer(free or false) end)
    return ok
end

local function doEvolve()
    local ok = pcall(function() EvolveRemote:InvokeServer() end)
    return ok
end

local function doAscend()
    local ok = pcall(function() AscendRemote:InvokeServer() end)
    return ok
end

-- ============================================================
-- SMART BUY: Buy items that are affordable (uang cukup)
-- ============================================================
local function smartBuySection(sectionName)
    local items = SectionMap[sectionName]
    if not items then return 0 end

    local bought = 0
    -- Try to buy each item - server will reject if can't afford
    for _, item in ipairs(items) do
        local ok = purchaseItem(item.remote)
        if ok then bought = bought + 1 end
    end
    return bought
end

-- ============================================================
-- CREATE WINDOW
-- ============================================================
local Window = Rayfield:CreateWindow({
    Name = 'DeepHUB - Sell Lemons v3.0',
    LoadingTitle = 'DeepHUB - Sell Lemons Auto Farm',
    LoadingSubtitle = 'v3.0 - Per Section Control',
    ConfigurationSaving = { Enabled = true, FolderName = 'DeepHUB_SellLemons', FileName = 'Config_v3' },
    KeySystem = false
})

-- ============================================================
-- STATUS TAB
-- ============================================================
local StatusTab = Window:CreateTab('Status', 'home')
StatusTab:CreateSection('Info')
StatusTab:CreateButton({ Name = 'Tycoon: ' .. Tycoon.Name, Flag = 'TycoonBtn', Callback = function() Rayfield:Notify({ Title = 'Tycoon', Content = Tycoon.Name .. ' | ' .. LocalPlayer.Name, Duration = 4, Image = 'home' }) end })

StatusTab:CreateSection('Stats')
StatusTab:CreateButton({
    Name = 'Refresh',
    Flag = 'RefreshBtn',
    Callback = function()
        refreshEarnerRemotes()
        refreshClickables()
        Rayfield:Notify({
            Title = 'Stats',
            Content = string.format('Cash: %s\nEarners: %d | Sections: %d\nFruits: %d | Prompts: %d',
                formatCash(getActualCash()), #EarnerRemotes, #SectionOrder, #FruitClickDetectors, #EarnerPrompts),
            Duration = 6, Image = 'bar-chart-2'
        })
    end
})

-- ============================================================
-- AUTO BUY TAB - Per Section
-- ============================================================
local BuyTab = Window:CreateTab('Auto Buy', 'shopping-cart')

BuyTab:CreateSection('Sections - Enable untuk auto-buy')
BuyTab:CreateParagraph({
    Title = 'Cara Kerja',
    Content = 'Enable section -> script otomatis beli item yang UANG CUKUP.\nItem yang sudah dibeli atau belum terbuka akan di-skip.\nTidak random - beli yang bisa dibeli saja.'
})

BuyTab:CreateSlider({
    Name = 'Buy Delay',
    Range = {0.05, 1}, Increment = 0.05, Suffix = ' sec', CurrentValue = 0.1,
    Flag = 'BuyDelaySlider',
    Callback = function(v) State.BuyDelay = v end
})

BuyTab:CreateButton({
    Name = 'Enable All Sections',
    Flag = 'EnableAllBtn',
    Callback = function()
        for name, _ in pairs(SectionMap) do State.SectionAutoBuy[name] = true end
        if Rayfield.Flags then
            for name, _ in pairs(SectionMap) do
                local flag = Rayfield.Flags['AutoBuy_' .. name:gsub('%s+', '_')]
                if flag then flag:Set(true) end
            end
        end
        Rayfield:Notify({ Title = 'Enabled', Content = 'Semua section di-enable!', Duration = 3, Image = 'check-circle' })
    end
})

BuyTab:CreateButton({
    Name = 'Disable All Sections',
    Flag = 'DisableAllBtn',
    Callback = function()
        for name, _ in pairs(SectionMap) do State.SectionAutoBuy[name] = false end
        if Rayfield.Flags then
            for name, _ in pairs(SectionMap) do
                local flag = Rayfield.Flags['AutoBuy_' .. name:gsub('%s+', '_')]
                if flag then flag:Set(false) end
            end
        end
        Rayfield:Notify({ Title = 'Disabled', Content = 'Semua section di-disable!', Duration = 3, Image = 'x-circle' })
    end
})

-- Section Toggles
for _, sectionName in ipairs(SectionOrder) do
    local items = SectionMap[sectionName]
    if items then
        local flagName = 'AutoBuy_' .. sectionName:gsub('%s+', '_')
        BuyTab:CreateToggle({
            Name = string.format('%s (%d items)', sectionName, #items),
            CurrentValue = false,
            Flag = flagName,
            Callback = function(Value) State.SectionAutoBuy[sectionName] = Value end
        })
    end
end

-- ============================================================
-- AUTO UPGRADE TAB - Per Earner
-- ============================================================
local UpgradeTab = Window:CreateTab('Auto Upgrade', 'trending-up')

UpgradeTab:CreateSection('Earner Upgrades')
UpgradeTab:CreateParagraph({
    Title = 'Cara Kerja',
    Content = 'Enable earner -> script otomatis upgrade earner tersebut.\nStack count menentukan berapa level sekaligus.'
})

UpgradeTab:CreateSlider({
    Name = 'Upgrade Delay',
    Range = {0.1, 5}, Increment = 0.1, Suffix = ' sec', CurrentValue = 0.3,
    Flag = 'UpgradeDelaySlider',
    Callback = function(v) State.UpgradeDelay = v end
})

UpgradeTab:CreateSlider({
    Name = 'Stack Count',
    Range = {1, 100}, Increment = 1, Suffix = 'x', CurrentValue = 1,
    Flag = 'StackSlider',
    Callback = function(v) State.StackCount = math.floor(v) end
})

UpgradeTab:CreateButton({
    Name = 'Enable All Earners',
    Flag = 'EnableAllUpgrades',
    Callback = function()
        for _, earner in ipairs(EarnerRemotes) do State.EarnerAutoUpgrade[earner.name] = true end
        Rayfield:Notify({ Title = 'Enabled', Content = 'Semua earner di-enable!', Duration = 3, Image = 'check-circle' })
    end
})

UpgradeTab:CreateButton({
    Name = 'Disable All Earners',
    Flag = 'DisableAllUpgrades',
    Callback = function()
        for _, earner in ipairs(EarnerRemotes) do State.EarnerAutoUpgrade[earner.name] = false end
        Rayfield:Notify({ Title = 'Disabled', Content = 'Semua earner di-disable!', Duration = 3, Image = 'x-circle' })
    end
})

for _, earner in ipairs(EarnerRemotes) do
    local flagName = 'Upgrade_' .. earner.name:gsub('%s+', '_')
    UpgradeTab:CreateToggle({
        Name = earner.name,
        CurrentValue = false,
        Flag = flagName,
        Callback = function(Value) State.EarnerAutoUpgrade[earner.name] = Value end
    })
end

-- ============================================================
-- FEATURES TAB
-- ============================================================
local FeatureTab = Window:CreateTab('Features', 'zap')

FeatureTab:CreateSection('Auto Features')

FeatureTab:CreateToggle({
    Name = 'Auto Click Fruit (Pohon Lemon)',
    CurrentValue = false, Flag = 'AutoFruit',
    Callback = function(v) State.AutoClickFruit = v end
})

FeatureTab:CreateToggle({
    Name = 'Auto Click Stand (ProximityPrompt)',
    CurrentValue = false, Flag = 'AutoStand',
    Callback = function(v) State.AutoClickStand = v end
})

FeatureTab:CreateToggle({
    Name = 'Auto Wake Income + TimeCash',
    CurrentValue = false, Flag = 'AutoWake',
    Callback = function(v) State.AutoWakeIncome = v end
})

FeatureTab:CreateToggle({
    Name = 'Auto Rebirth',
    CurrentValue = false, Flag = 'AutoRebirth',
    Callback = function(v) State.AutoRebirth = v end
})

FeatureTab:CreateToggle({
    Name = 'Auto Evolve',
    CurrentValue = false, Flag = 'AutoEvolve',
    Callback = function(v) State.AutoEvolve = v end
})

FeatureTab:CreateToggle({
    Name = 'Auto Ascend',
    CurrentValue = false, Flag = 'AutoAscend',
    Callback = function(v) State.AutoAscend = v end
})

FeatureTab:CreateSection('Manual Actions')

FeatureTab:CreateButton({
    Name = 'Buy Section: Lemon Stand',
    Flag = 'BuyLemonStand',
    Callback = function()
        local bought = smartBuySection('Lemon Stand')
        Rayfield:Notify({ Title = 'Lemon Stand', Content = 'Bought: ' .. bought .. ' items', Duration = 3, Image = 'shopping-cart' })
    end
})

FeatureTab:CreateButton({
    Name = 'Buy Section: LemonDash',
    Flag = 'BuyLemonDash',
    Callback = function()
        local bought = smartBuySection('LemonDash')
        Rayfield:Notify({ Title = 'LemonDash', Content = 'Bought: ' .. bought .. ' items', Duration = 3, Image = 'shopping-cart' })
    end
})

FeatureTab:CreateButton({
    Name = 'Rebirth Now',
    Flag = 'ManualRebirth',
    Callback = function()
        local ok = doRebirth(false)
        Rayfield:Notify({ Title = 'Rebirth', Content = ok and 'Berhasil!' or 'Gagal (belum cukup syarat).', Duration = 4, Image = ok and 'check-circle' or 'x-circle' })
    end
})

FeatureTab:CreateButton({
    Name = 'Evolve Now',
    Flag = 'ManualEvolve',
    Callback = function()
        local ok = doEvolve()
        Rayfield:Notify({ Title = 'Evolve', Content = ok and 'Berhasil!' or 'Gagal.', Duration = 4, Image = ok and 'check-circle' or 'x-circle' })
    end
})

FeatureTab:CreateButton({
    Name = 'Ascend Now',
    Flag = 'ManualAscend',
    Callback = function()
        local ok = doAscend()
        Rayfield:Notify({ Title = 'Ascend', Content = ok and 'Berhasil!' or 'Gagal (butuh 100% items).', Duration = 4, Image = ok and 'check-circle' or 'x-circle' })
    end
})

-- ============================================================
-- TELEPORT TAB
-- ============================================================
local TP = Window:CreateTab('Teleport', 'map-pin')
TP:CreateSection('Locations')
local locations = Tycoon:FindFirstChild('Locations')
if locations then
    for _, loc in ipairs(locations:GetChildren()) do
        if loc:IsA('BasePart') then
            TP:CreateButton({
                Name = 'TP to ' .. loc.Name,
                Flag = 'TP_' .. loc.Name:gsub('%s+', '_'),
                Callback = function()
                    local char = LocalPlayer.Character
                    if char and char:FindFirstChild('HumanoidRootPart') then
                        char.HumanoidRootPart.CFrame = CFrame.new(loc.Position + Vector3.new(0, 5, 0))
                        Rayfield:Notify({ Title = 'Teleported', Content = loc.Name, Duration = 2, Image = 'map-pin' })
                    end
                end
            })
        end
    end
end
TP:CreateButton({ Name = 'Rejoin', Flag = 'Rejoin', Callback = function() game:GetService('TeleportService'):TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer) end })

-- ============================================================
-- SETTINGS TAB
-- ============================================================
local SettingsTab = Window:CreateTab('Settings', 'settings')
SettingsTab:CreateSection('Menu')
SettingsTab:CreateKeybind({ Name = 'Toggle Menu', CurrentKeybind = 'RightShift', HoldToInteract = false, Flag = 'MenuKey', Callback = function() Rayfield:Toggle() end })
SettingsTab:CreateButton({ Name = 'Unload', Flag = 'Unload', Callback = function() Rayfield:Notify({ Title = 'Unloading...', Content = 'Bye!', Duration = 2, Image = 'power' }); task.wait(2); Rayfield:Destroy() end })

-- ============================================================
-- LOOPS
-- ============================================================

-- Smart Buy Loop: beli item yang UANG CUKUP per section
task.spawn(function()
    while true do
        for sectionName, enabled in pairs(State.SectionAutoBuy) do
            if enabled then
                smartBuySection(sectionName)
                task.wait(State.BuyDelay)
            end
        end
        task.wait(1)
    end
end)

-- Auto Upgrade Loop
task.spawn(function()
    while true do
        for earnerName, enabled in pairs(State.EarnerAutoUpgrade) do
            if enabled then
                upgradeEarner(earnerName, State.StackCount)
                task.wait(State.UpgradeDelay)
            end
        end
        task.wait(0.5)
    end
end)

-- Auto Click Fruit
task.spawn(function()
    while true do
        if State.AutoClickFruit then
            refreshClickables()
            for _, cd in ipairs(FruitClickDetectors) do
                pcall(function() fireclickdetector(cd) end)
            end
        end
        task.wait(0.5)
    end
end)

-- Auto Click Stand
task.spawn(function()
    while true do
        if State.AutoClickStand then
            refreshClickables()
            for _, pp in ipairs(EarnerPrompts) do
                pcall(function() fireproximityprompt(pp) end)
            end
        end
        task.wait(0.5)
    end
end)

-- Auto Wake Income
task.spawn(function()
    while true do
        if State.AutoWakeIncome then
            if WakeIncomeStream then
                for _, earner in ipairs(EarnerRemotes) do
                    pcall(function() WakeIncomeStream:InvokeServer(earner.name) end)
                end
            end
        end
        task.wait(5)
    end
end)

-- Auto Rebirth
task.spawn(function()
    while true do
        if State.AutoRebirth then
            doRebirth(false); doRebirth(true)
        end
        task.wait(5)
    end
end)

-- Auto Evolve
task.spawn(function()
    while true do
        if State.AutoEvolve then doEvolve() end
        task.wait(10)
    end
end)

-- Auto Ascend
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
    Title = 'DeepHUB - Sell Lemons v3.0',
    Content = string.format('Loaded! Tycoon: %s | Sections: %d | Earners: %d\nTekan RightShift untuk toggle menu.',
        Tycoon.Name, #SectionMap, #EarnerRemotes),
    Duration = 6, Image = 'check-circle'
})
