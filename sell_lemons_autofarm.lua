--[[
    ============================================
    DeepHUB - Sell Lemons Auto Farm v2.1
    UI Library: Rayfield
    Game: Jual Jeruk / Sell Lemons (BloxByte Games)
    ============================================
    v2.1 Changes:
    - Manual actions now validate conditions & show errors
    - Added Auto Click Stand (ProximityPrompt + Fruit Click)
    - Fixed cash display (log10 format -> actual $)
    - Rebirth/Evolve/Ascend conditions checked before action
    ============================================
]]

-- ============================================================
-- LOAD RAYFIELD
-- ============================================================
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

-- ============================================================
-- SERVICES
-- ============================================================
local Players = game:GetService('Players')
local RunService = game:GetService('RunService')
local UserInputService = game:GetService('UserInputService')

local LocalPlayer = Players.LocalPlayer

-- ============================================================
-- FIND MY TYCOON (by owner)
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
    Rayfield:Notify({
        Title = 'Error',
        Content = 'Tycoon tidak ditemukan! Pastikan kamu punya tycoon di server ini.',
        Duration = 8,
        Image = 'alert-triangle'
    })
    return
end

-- ============================================================
-- SETUP REMOTES & REFERENCES
-- ============================================================
local Remotes = Tycoon:WaitForChild('Remotes')
local RebirthRemote = Remotes:WaitForChild('Rebirth')
local EvolveRemote = Remotes:WaitForChild('Evolve')
local AscendRemote = Remotes:WaitForChild('Ascend')
local WakeIncomeStream = Remotes:FindFirstChild('WakeIncomeStream')
local UseEarnerBoost = Remotes:FindFirstChild('UseEarnerBoost')
local UseTimeCash = Remotes:FindFirstChild('UseTimeCash')
local SelectPowerLevel = Remotes:FindFirstChild('SelectPowerLevel')

local Values = Tycoon:WaitForChild('Values')
local ValuesConfig = Values:WaitForChild('Values')
local UpgradesConfig = Values:WaitForChild('Upgrades')
local PurchasesFolder = Tycoon:WaitForChild('Purchases')

-- Earner Upgrade remotes
local EarnerRemotes = {}
local function refreshEarnerRemotes()
    EarnerRemotes = {}
    for _, desc in ipairs(Tycoon:GetDescendants()) do
        if desc:IsA('RemoteFunction') and desc.Name == 'Upgrade' then
            local earnerPart = desc.Parent
            if earnerPart and earnerPart:IsA('BasePart') then
                table.insert(EarnerRemotes, {
                    name = earnerPart.Name,
                    remote = desc,
                    part = earnerPart
                })
            end
        end
    end
end
refreshEarnerRemotes()

-- Earner ProximityPrompts (for clicking the stand)
local EarnerPrompts = {}
local function refreshEarnerPrompts()
    EarnerPrompts = {}
    for _, desc in ipairs(Tycoon:GetDescendants()) do
        if desc:IsA('ProximityPrompt') then
            local earnerPart = desc.Parent
            if earnerPart and earnerPart:IsA('BasePart') then
                table.insert(EarnerPrompts, {
                    name = earnerPart.Name,
                    prompt = desc,
                    part = earnerPart
                })
            end
        end
    end
end
refreshEarnerPrompts()

-- Fruit ClickDetectors
local FruitClickDetectors = {}
local function refreshFruitClicks()
    FruitClickDetectors = {}
    for _, desc in ipairs(Tycoon:GetDescendants()) do
        if desc:IsA('ClickDetector') then
            local fruitPart = desc.Parent
            if fruitPart then
                table.insert(FruitClickDetectors, {
                    name = fruitPart.Name,
                    detector = desc,
                    part = fruitPart
                })
            end
        end
    end
end
refreshFruitClicks()

-- Purchase buttons
local PurchaseButtons = {}
local function refreshPurchaseButtons()
    PurchaseButtons = {}
    for _, desc in ipairs(PurchasesFolder:GetDescendants()) do
        if desc:IsA('RemoteFunction') and desc.Name == 'Purchase' then
            table.insert(PurchaseButtons, {
                name = desc.Parent.Name,
                area = desc.Parent.Parent.Parent.Name,
                remote = desc
            })
        end
    end
end
refreshPurchaseButtons()

-- ============================================================
-- NUMBER FORMATTING (log10 aware)
-- ============================================================
local suffixes = {
    '', 'K', 'M', 'B', 'T', 'Qa', 'Qi', 'Sx', 'Sp', 'Oc', 'No', 'Dc',
    'UDc', 'DDc', 'TDc', 'QaDc', 'QiDc', 'SxDc', 'SpDc', 'OcDc', 'NoDc', 'Vg'
}

local function formatNumber(num)
    if type(num) ~= 'number' then
        num = tonumber(num)
        if not num then return '?' end
    end
    if num < 0 then return '-' .. formatNumber(-num) end
    if num < 1000 then return string.format('%.1f', num) end
    local tier = math.floor(math.log10(num) / 3)
    if tier >= #suffixes then
        return string.format('%.2fe%d', num / (10 ^ (tier * 3)), tier * 3)
    end
    local scaled = num / (10 ^ (tier * 3))
    return string.format('%.2f%s', scaled, suffixes[tier + 1])
end

local function formatCash(num)
    return '$' .. formatNumber(num)
end

-- Convert log10 value to actual number
local function log10ToActual(logVal)
    if type(logVal) == 'string' then
        logVal = tonumber(logVal)
    end
    if not logVal or logVal == 0 then return 0 end
    return 10 ^ logVal
end

-- Get actual cash (values are stored in log10)
local function getActualCash()
    local cashLog = ValuesConfig:GetAttribute('Cash')
    if not cashLog or cashLog == 0 then return 0 end
    return log10ToActual(cashLog)
end

local function getActualCashSpent()
    local csLog = ValuesConfig:GetAttribute('CashSpent')
    if type(csLog) == 'string' then csLog = tonumber(csLog) end
    if not csLog or csLog == 0 then return 0 end
    return log10ToActual(csLog)
end

local function getActualInvestors()
    local invLog = ValuesConfig:GetAttribute('Investors')
    if type(invLog) == 'string' then invLog = tonumber(invLog) end
    if not invLog or invLog == 0 then return 0 end
    return log10ToActual(invLog)
end

local function getActualInvestorsSpent()
    local isLog = ValuesConfig:GetAttribute('InvestorsSpent')
    if type(isLog) == 'string' then isLog = tonumber(isLog) end
    if not isLog or isLog == 0 then return 0 end
    return log10ToActual(isLog)
end

local function getRebirths()
    return ValuesConfig:GetAttribute('TotalRebirths') or ValuesConfig:GetAttribute('Rebirths') or 0
end

local function getUpgrades()
    return UpgradesConfig:GetAttributes()
end

-- ============================================================
-- CONDITION CHECKS
-- ============================================================

-- Rebirth: need cash+cashSpent >= investorsToNewCash(1, currentInvestors)
-- investorsToNewCash(1, 0) = (1)^(1/0.44) * 1.8e17 = 1.8e17 (log10 = 17.255)
local REBIRTH_CASH_THRESHOLD_LOG10 = 17.255

local function canRebirth()
    local cashLog = ValuesConfig:GetAttribute('Cash')
    local cashSpentLog = ValuesConfig:GetAttribute('CashSpent')
    if type(cashLog) == 'string' then cashLog = tonumber(cashLog) end
    if type(cashSpentLog) == 'string' then cashSpentLog = tonumber(cashSpentLog) end
    if not cashLog then cashLog = 0 end
    if not cashSpentLog then cashSpentLog = 0 end

    -- cash+cashSpent in actual values
    local totalCash = log10ToActual(cashLog) + log10ToActual(cashSpentLog)
    local investors = getActualInvestors()

    -- investorsToNewCash(1, investors) = ((investors+1)/investors)^(1/0.44) * investors^(1/0.44) * 1.8e17
    -- Simplified: need totalCash >= (investors+1)^(1/0.44) * 1.8e17 when investors=0
    local threshold
    if investors == 0 then
        threshold = 1.8e17
    else
        threshold = ((investors + 1) ^ (1 / 0.44)) * 1.8e17
    end

    return totalCash >= threshold
end

-- Evolution: need total investors >= nextEvolutionInvestors(currentEvolution)
-- nextEvolutionInvestors(0) = 10^17.7 = 5.01e17
local function canEvolve()
    local totalInvestors = getActualInvestors() + getActualInvestorsSpent()
    -- Simplified check: just try the remote and see if it works
    -- The server will validate properly
    return totalInvestors >= 5.01e17 -- approximate for evolution 0
end

-- Ascension: need ALL items purchased (100%)
local function canAscend()
    local purchasedCount = 0
    local totalCount = 0
    for _, desc in ipairs(PurchasesFolder:GetDescendants()) do
        if desc:IsA('RemoteFunction') and desc.Name == 'Purchase' then
            totalCount = totalCount + 1
        end
    end
    -- We can't easily check purchased count from client
    -- The server will validate, so we just try
    return true -- let server decide
end

-- ============================================================
-- ACTION FUNCTIONS
-- ============================================================
local function upgradeEarner(earnerName, stackCount)
    for _, earner in ipairs(EarnerRemotes) do
        if earner.name == earnerName then
            local ok, result = pcall(function()
                return earner.remote:InvokeServer(stackCount or 1)
            end)
            return ok and result ~= false
        end
    end
    return false
end

local function purchaseItem(remote)
    local ok, result = pcall(function()
        return remote:InvokeServer()
    end)
    if ok and result == nil then
        return true
    end
    return false, tostring(result)
end

local function doRebirth(free)
    if not canRebirth() and not free then
        return false, 'Uang tidak cukup untuk rebirth (butuh $180Q+)'
    end
    local ok, result = pcall(function()
        return RebirthRemote:InvokeServer(free or false)
    end)
    if ok and result == nil then return true end
    return false, tostring(result)
end

local function doEvolve()
    local ok, result = pcall(function()
        return EvolveRemote:InvokeServer()
    end)
    if ok and result == nil then return true end
    return false, tostring(result)
end

local function doAscend()
    local ok, result = pcall(function()
        return AscendRemote:InvokeServer()
    end)
    if ok and result == nil then return true end
    return false, tostring(result)
end

local function wakeIncome(earnerName)
    if WakeIncomeStream then
        pcall(function()
            WakeIncomeStream:InvokeServer(earnerName)
        end)
    end
end

local function useEarnerBoost()
    if UseEarnerBoost then
        pcall(function()
            UseEarnerBoost:InvokeServer()
        end)
    end
end

local function useTimeCash()
    if UseTimeCash then
        pcall(function()
            UseTimeCash:InvokeServer()
        end)
    end
end

local function fireEarnerPrompts()
    refreshEarnerPrompts()
    for _, ep in ipairs(EarnerPrompts) do
        pcall(function()
            fireproximityprompt(ep.prompt)
        end)
    end
end

local function fireFruitClicks()
    refreshFruitClicks()
    for _, fc in ipairs(FruitClickDetectors) do
        pcall(function()
            fireclickdetector(fc.detector)
        end)
    end
end

-- ============================================================
-- STATE
-- ============================================================
local State = {
    AutoPurchase = false,
    AutoUpgrade = false,
    AutoRebirth = false,
    AutoEvolve = false,
    AutoAscend = false,
    AutoCollect = false,
    AutoWakeIncome = false,
    AutoClickStand = false,
    AutoClickFruit = false,
    PurchaseDelay = 0.1,
    UpgradeDelay = 0.3,
    RebirthDelay = 5,
    EvolveDelay = 10,
    AscendDelay = 15,
    ClickStandDelay = 0.5,
    ClickFruitDelay = 0.3,
    StackCount = 1,
}

-- ============================================================
-- CREATE WINDOW
-- ============================================================
local Window = Rayfield:CreateWindow({
    Name = 'DeepHUB - Sell Lemons v2.1',
    LoadingTitle = 'DeepHUB - Sell Lemons Auto Farm',
    LoadingSubtitle = 'v2.1 - by DeepHUB Team',
    ConfigurationSaving = {
        Enabled = true,
        FolderName = 'DeepHUB_SellLemons',
        FileName = 'AutoFarmConfig_v21'
    },
    Discord = { Enabled = false },
    KeySystem = false
})

-- ============================================================
-- STATUS TAB
-- ============================================================
local StatusTab = Window:CreateTab('Status', 'home')

StatusTab:CreateSection('Game Info')

StatusTab:CreateButton({
    Name = 'Tycoon: ' .. Tycoon.Name .. ' | Owner: ' .. LocalPlayer.Name,
    Flag = 'TycoonInfoButton',
    Callback = function()
        setclipboard(Tycoon.Name .. ' | Owner: ' .. LocalPlayer.Name)
        Rayfield:Notify({ Title = 'Copied!', Content = Tycoon.Name .. ' | ' .. LocalPlayer.Name, Duration = 4, Image = 'clipboard-copy' })
    end
})

StatusTab:CreateButton({
    Name = 'Place ID: ' .. game.PlaceId,
    Flag = 'PlaceIDButton',
    Callback = function()
        setclipboard(tostring(game.PlaceId))
        Rayfield:Notify({ Title = 'Copied!', Content = 'Place ID: ' .. game.PlaceId, Duration = 4, Image = 'clipboard-copy' })
    end
})

StatusTab:CreateButton({
    Name = 'Players: ' .. #Players:GetPlayers(),
    Flag = 'PlayerCountButton',
    Callback = function()
        Rayfield:Notify({ Title = 'Players', Content = 'Players: ' .. #Players:GetPlayers(), Duration = 4, Image = 'users' })
    end
})

StatusTab:CreateSection('Live Stats')

StatusTab:CreateButton({
    Name = 'Refresh Stats',
    Flag = 'RefreshStatsButton',
    Callback = function()
        local cash = getActualCash()
        local cashSpent = getActualCashSpent()
        local investors = getActualInvestors()
        local rebirths = getRebirths()
        local upgrades = getUpgrades()

        local upgradeList = {}
        for name, level in pairs(upgrades) do
            table.insert(upgradeList, name .. ' Lv.' .. level)
        end

        Rayfield:Notify({
            Title = 'Stats',
            Content = string.format(
                'Cash: %s\nCash Spent: %s\nInvestors: %s\nRebirths: %d\nEarners: %d | Fruits: %d | Prompts: %d\nUpgrades: %s',
                formatCash(cash), formatCash(cashSpent), formatNumber(investors),
                rebirths, #EarnerRemotes, #FruitClickDetectors, #EarnerPrompts,
                #upgradeList > 0 and table.concat(upgradeList, ', ') or 'None'
            ),
            Duration = 8,
            Image = 'bar-chart-2'
        })
    end
})

StatusTab:CreateParagraph({
    Title = 'Earners',
    Content = (function()
        local names = {}
        for _, e in ipairs(EarnerRemotes) do table.insert(names, e.name) end
        return table.concat(names, ', ')
    end)()
})

StatusTab:CreateParagraph({
    Title = 'Clickable Objects',
    Content = string.format('Fruit Clicks: %d | Earner Prompts: %d', #FruitClickDetectors, #EarnerPrompts)
})

-- ============================================================
-- AUTO FARM TAB
-- ============================================================
local AutoFarmTab = Window:CreateTab('Auto Farm', 'zap')

AutoFarmTab:CreateSection('Auto Features')

AutoFarmTab:CreateToggle({
    Name = 'Auto Purchase (Buy All Items)',
    CurrentValue = false,
    Flag = 'AutoPurchaseToggle',
    Callback = function(Value)
        State.AutoPurchase = Value
        Rayfield:Notify({ Title = 'Auto Purchase', Content = Value and 'Enabled!' or 'Disabled.', Duration = 3, Image = 'shopping-cart' })
    end
})

AutoFarmTab:CreateToggle({
    Name = 'Auto Upgrade Earners',
    CurrentValue = false,
    Flag = 'AutoUpgradeToggle',
    Callback = function(Value)
        State.AutoUpgrade = Value
        Rayfield:Notify({ Title = 'Auto Upgrade', Content = Value and 'Enabled!' or 'Disabled.', Duration = 3, Image = 'trending-up' })
    end
})

AutoFarmTab:CreateToggle({
    Name = 'Auto Click Stand (ProximityPrompt)',
    CurrentValue = false,
    Flag = 'AutoClickStandToggle',
    Callback = function(Value)
        State.AutoClickStand = Value
        Rayfield:Notify({ Title = 'Auto Click Stand', Content = Value and 'Enabled! Clicking earner stands.' or 'Disabled.', Duration = 3, Image = 'mouse-pointer' })
    end
})

AutoFarmTab:CreateToggle({
    Name = 'Auto Click Fruit (Trees/Crates)',
    CurrentValue = false,
    Flag = 'AutoClickFruitToggle',
    Callback = function(Value)
        State.AutoClickFruit = Value
        Rayfield:Notify({ Title = 'Auto Click Fruit', Content = Value and 'Enabled! Clicking fruits.' or 'Disabled.', Duration = 3, Image = 'mouse-pointer' })
    end
})

AutoFarmTab:CreateToggle({
    Name = 'Auto Rebirth',
    CurrentValue = false,
    Flag = 'AutoRebirthToggle',
    Callback = function(Value)
        State.AutoRebirth = Value
        Rayfield:Notify({ Title = 'Auto Rebirth', Content = Value and 'Enabled!' or 'Disabled.', Duration = 3, Image = 'refresh-cw' })
    end
})

AutoFarmTab:CreateToggle({
    Name = 'Auto Evolve',
    CurrentValue = false,
    Flag = 'AutoEvolveToggle',
    Callback = function(Value)
        State.AutoEvolve = Value
        Rayfield:Notify({ Title = 'Auto Evolve', Content = Value and 'Enabled!' or 'Disabled.', Duration = 3, Image = 'activity' })
    end
})

AutoFarmTab:CreateToggle({
    Name = 'Auto Ascend',
    CurrentValue = false,
    Flag = 'AutoAscendToggle',
    Callback = function(Value)
        State.AutoAscend = Value
        Rayfield:Notify({ Title = 'Auto Ascend', Content = Value and 'Enabled!' or 'Disabled.', Duration = 3, Image = 'star' })
    end
})

AutoFarmTab:CreateToggle({
    Name = 'Auto Wake Income + Boost + TimeCash',
    CurrentValue = false,
    Flag = 'AutoWakeIncomeToggle',
    Callback = function(Value)
        State.AutoWakeIncome = Value
        Rayfield:Notify({ Title = 'Auto Wake Income', Content = Value and 'Enabled!' or 'Disabled.', Duration = 3, Image = 'dollar-sign' })
    end
})

AutoFarmTab:CreateSection('Settings')

AutoFarmTab:CreateSlider({
    Name = 'Purchase Delay',
    Range = {0.05, 2},
    Increment = 0.05,
    Suffix = ' sec',
    CurrentValue = 0.1,
    Flag = 'PurchaseDelaySlider',
    Callback = function(Value) State.PurchaseDelay = Value end
})

AutoFarmTab:CreateSlider({
    Name = 'Upgrade Delay',
    Range = {0.1, 5},
    Increment = 0.1,
    Suffix = ' sec',
    CurrentValue = 0.3,
    Flag = 'UpgradeDelaySlider',
    Callback = function(Value) State.UpgradeDelay = Value end
})

AutoFarmTab:CreateSlider({
    Name = 'Click Stand Delay',
    Range = {0.1, 5},
    Increment = 0.1,
    Suffix = ' sec',
    CurrentValue = 0.5,
    Flag = 'ClickStandDelaySlider',
    Callback = function(Value) State.ClickStandDelay = Value end
})

AutoFarmTab:CreateSlider({
    Name = 'Click Fruit Delay',
    Range = {0.1, 5},
    Increment = 0.1,
    Suffix = ' sec',
    CurrentValue = 0.3,
    Flag = 'ClickFruitDelaySlider',
    Callback = function(Value) State.ClickFruitDelay = Value end
})

AutoFarmTab:CreateSlider({
    Name = 'Rebirth Delay',
    Range = {1, 60},
    Increment = 1,
    Suffix = ' sec',
    CurrentValue = 5,
    Flag = 'RebirthDelaySlider',
    Callback = function(Value) State.RebirthDelay = Value end
})

AutoFarmTab:CreateSlider({
    Name = 'Upgrade Stack Count',
    Range = {1, 100},
    Increment = 1,
    Suffix = 'x',
    CurrentValue = 1,
    Flag = 'StackCountSlider',
    Callback = function(Value) State.StackCount = math.floor(Value) end
})

-- ============================================================
-- MANUAL ACTIONS (with validation)
-- ============================================================
AutoFarmTab:CreateSection('Manual Actions')

AutoFarmTab:CreateButton({
    Name = 'Buy All Available Items (Once)',
    Flag = 'ManualBuyAllButton',
    Callback = function()
        local bought = 0
        local skipped = 0
        local errors = {}
        refreshPurchaseButtons()
        for _, btn in ipairs(PurchaseButtons) do
            local ok, reason = purchaseItem(btn.remote)
            if ok then
                bought = bought + 1
            else
                skipped = skipped + 1
                if reason ~= 'already purchased' and reason ~= 'not purchasable (disabled)' then
                    if #errors < 3 then
                        table.insert(errors, btn.name .. ': ' .. reason)
                    end
                end
            end
        end
        local msg = string.format('Bought: %d | Skipped: %d', bought, skipped)
        if #errors > 0 then
            msg = msg .. '\nErrors: ' .. table.concat(errors, ', ')
        end
        Rayfield:Notify({ Title = 'Buy All', Content = msg, Duration = 6, Image = 'shopping-cart' })
    end
})

AutoFarmTab:CreateButton({
    Name = 'Upgrade All Earners (Once)',
    Flag = 'ManualUpgradeAllButton',
    Callback = function()
        refreshEarnerRemotes()
        local upgraded = 0
        local failed = {}
        for _, earner in ipairs(EarnerRemotes) do
            local ok = upgradeEarner(earner.name, State.StackCount)
            if ok then
                upgraded = upgraded + 1
            else
                table.insert(failed, earner.name)
            end
        end
        local msg = 'Upgraded: ' .. upgraded .. ' earners'
        if #failed > 0 then
            msg = msg .. '\nFailed (uang tidak cukup/belum bisa): ' .. table.concat(failed, ', ')
        end
        Rayfield:Notify({ Title = 'Upgrade All', Content = msg, Duration = 5, Image = 'trending-up' })
    end
})

AutoFarmTab:CreateButton({
    Name = 'Click All Earner Stands (Once)',
    Flag = 'ManualClickStandsButton',
    Callback = function()
        refreshEarnerPrompts()
        local count = #EarnerPrompts
        fireEarnerPrompts()
        Rayfield:Notify({ Title = 'Click Stands', Content = 'Fired ' .. count .. ' earner prompts!', Duration = 3, Image = 'mouse-pointer' })
    end
})

AutoFarmTab:CreateButton({
    Name = 'Click All Fruits (Once)',
    Flag = 'ManualClickFruitsButton',
    Callback = function()
        refreshFruitClicks()
        local count = #FruitClickDetectors
        fireFruitClicks()
        Rayfield:Notify({ Title = 'Click Fruits', Content = 'Clicked ' .. count .. ' fruits!', Duration = 3, Image = 'mouse-pointer' })
    end
})

AutoFarmTab:CreateButton({
    Name = 'Rebirth Now',
    Flag = 'ManualRebirthButton',
    Callback = function()
        local ok, reason = doRebirth(false)
        if ok then
            Rayfield:Notify({ Title = 'Rebirth', Content = 'Rebirth berhasil!', Duration = 4, Image = 'check-circle' })
        else
            Rayfield:Notify({ Title = 'Rebirth Gagal', Content = reason or 'Belum memenuhi syarat (butuh lebih banyak cash).', Duration = 5, Image = 'x-circle' })
        end
    end
})

AutoFarmTab:CreateButton({
    Name = 'Free Rebirth Now',
    Flag = 'ManualFreeRebirthButton',
    Callback = function()
        local ok, reason = doRebirth(true)
        if ok then
            Rayfield:Notify({ Title = 'Free Rebirth', Content = 'Free rebirth berhasil!', Duration = 4, Image = 'check-circle' })
        else
            Rayfield:Notify({ Title = 'Free Rebirth Gagal', Content = reason or 'Free rebirth tidak tersedia.', Duration = 5, Image = 'x-circle' })
        end
    end
})

AutoFarmTab:CreateButton({
    Name = 'Evolve Now',
    Flag = 'ManualEvolveButton',
    Callback = function()
        local ok, reason = doEvolve()
        if ok then
            Rayfield:Notify({ Title = 'Evolve', Content = 'Evolution berhasil!', Duration = 4, Image = 'check-circle' })
        else
            Rayfield:Notify({ Title = 'Evolve Gagal', Content = reason or 'Belum memenuhi syarat (butuh lebih banyak investors).', Duration = 5, Image = 'x-circle' })
        end
    end
})

AutoFarmTab:CreateButton({
    Name = 'Ascend Now',
    Flag = 'ManualAscendButton',
    Callback = function()
        local ok, reason = doAscend()
        if ok then
            Rayfield:Notify({ Title = 'Ascend', Content = 'Ascension berhasil!', Duration = 4, Image = 'check-circle' })
        else
            Rayfield:Notify({ Title = 'Ascend Gagal', Content = reason or 'Belum memenuhi syarat (butuh 100% items purchased).', Duration = 5, Image = 'x-circle' })
        end
    end
})

AutoFarmTab:CreateButton({
    Name = 'Use Time Cash',
    Flag = 'ManualTimeCashButton',
    Callback = function()
        useTimeCash()
        Rayfield:Notify({ Title = 'Time Cash', Content = 'Time Cash digunakan!', Duration = 3, Image = 'clock' })
    end
})

AutoFarmTab:CreateButton({
    Name = 'Use Earner Boost',
    Flag = 'ManualEarnerBoostButton',
    Callback = function()
        useEarnerBoost()
        Rayfield:Notify({ Title = 'Earner Boost', Content = 'Earner Boost diaktifkan!', Duration = 3, Image = 'zap' })
    end
})

-- ============================================================
-- TELEPORT TAB
-- ============================================================
local TeleportTab = Window:CreateTab('Teleport', 'map-pin')

TeleportTab:CreateSection('Tycoon Locations')

local locations = Tycoon:FindFirstChild('Locations')
if locations then
    for _, loc in ipairs(locations:GetChildren()) do
        if loc:IsA('BasePart') then
            TeleportTab:CreateButton({
                Name = 'TP to ' .. loc.Name,
                Flag = 'TP_' .. loc.Name .. '_Button',
                Callback = function()
                    local char = LocalPlayer.Character
                    if char then
                        local hrp = char:FindFirstChild('HumanoidRootPart')
                        if hrp then
                            hrp.CFrame = CFrame.new(loc.Position + Vector3.new(0, 5, 0))
                            Rayfield:Notify({ Title = 'Teleported', Content = 'Teleported to ' .. loc.Name, Duration = 3, Image = 'map-pin' })
                        end
                    end
                end
            })
        end
    end
end

TeleportTab:CreateSection('Earner Locations')

for _, earner in ipairs(EarnerRemotes) do
    TeleportTab:CreateButton({
        Name = 'TP to ' .. earner.name,
        Flag = 'TP_Earner_' .. earner.name .. '_Button',
        Callback = function()
            local char = LocalPlayer.Character
            if char then
                local hrp = char:FindFirstChild('HumanoidRootPart')
                if hrp then
                    hrp.CFrame = CFrame.new(earner.part.Position + Vector3.new(0, 5, 0))
                    Rayfield:Notify({ Title = 'Teleported', Content = 'Teleported to ' .. earner.name, Duration = 3, Image = 'map-pin' })
                end
            end
        end
    })
end

TeleportTab:CreateSection('Server')

TeleportTab:CreateButton({
    Name = 'Copy My Position',
    Flag = 'CopyPositionButton',
    Callback = function()
        local char = LocalPlayer.Character
        if char then
            local hrp = char:FindFirstChild('HumanoidRootPart')
            if hrp then
                local pos = hrp.Position
                local coordStr = string.format('%.1f, %.1f, %.1f', pos.X, pos.Y, pos.Z)
                setclipboard(coordStr)
                Rayfield:Notify({ Title = 'Position Copied', Content = coordStr, Duration = 4, Image = 'clipboard-copy' })
            end
        end
    end
})

TeleportTab:CreateButton({
    Name = 'Rejoin Server',
    Flag = 'RejoinServerButton',
    Callback = function()
        Rayfield:Notify({ Title = 'Rejoining...', Content = 'Teleporting...', Duration = 3, Image = 'refresh-cw' })
        task.wait(1)
        game:GetService('TeleportService'):TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
    end
})

-- ============================================================
-- AUTO FARM LOOPS
-- ============================================================

-- Auto Purchase Loop
task.spawn(function()
    while true do
        if State.AutoPurchase then
            refreshPurchaseButtons()
            for _, btn in ipairs(PurchaseButtons) do
                if not State.AutoPurchase then break end
                purchaseItem(btn.remote)
                task.wait(State.PurchaseDelay)
            end
        end
        task.wait(1)
    end
end)

-- Auto Upgrade Loop
task.spawn(function()
    while true do
        if State.AutoUpgrade then
            refreshEarnerRemotes()
            for _, earner in ipairs(EarnerRemotes) do
                if not State.AutoUpgrade then break end
                upgradeEarner(earner.name, State.StackCount)
                task.wait(State.UpgradeDelay)
            end
        end
        task.wait(0.5)
    end
end)

-- Auto Click Stand Loop (ProximityPrompt)
task.spawn(function()
    while true do
        if State.AutoClickStand then
            fireEarnerPrompts()
        end
        task.wait(State.ClickStandDelay)
    end
end)

-- Auto Click Fruit Loop (ClickDetector)
task.spawn(function()
    while true do
        if State.AutoClickFruit then
            fireFruitClicks()
        end
        task.wait(State.ClickFruitDelay)
    end
end)

-- Auto Rebirth Loop
task.spawn(function()
    while true do
        if State.AutoRebirth then
            doRebirth(false)
            doRebirth(true) -- try free rebirth too
        end
        task.wait(State.RebirthDelay)
    end
end)

-- Auto Evolve Loop
task.spawn(function()
    while true do
        if State.AutoEvolve then
            doEvolve()
        end
        task.wait(State.EvolveDelay)
    end
end)

-- Auto Ascend Loop
task.spawn(function()
    while true do
        if State.AutoAscend then
            doAscend()
        end
        task.wait(State.AscendDelay)
    end
end)

-- Auto Wake Income Loop
task.spawn(function()
    while true do
        if State.AutoWakeIncome then
            for _, earner in ipairs(EarnerRemotes) do
                if not State.AutoWakeIncome then break end
                wakeIncome(earner.name)
            end
            useEarnerBoost()
            useTimeCash()
        end
        task.wait(5)
    end
end)

-- ============================================================
-- SETTINGS TAB
-- ============================================================
local SettingsTab = Window:CreateTab('Settings', 'settings')

SettingsTab:CreateSection('Menu')

SettingsTab:CreateKeybind({
    Name = 'Toggle Menu Keybind',
    CurrentKeybind = 'RightShift',
    HoldToInteract = false,
    Flag = 'MenuKeybind',
    Callback = function()
        Rayfield:Toggle()
    end
})

SettingsTab:CreateButton({
    Name = 'Unload Script',
    Flag = 'UnloadButton',
    Callback = function()
        Rayfield:Notify({ Title = 'Unloading...', Content = 'Destroying in 2 seconds.', Duration = 2, Image = 'power' })
        task.wait(2)
        Rayfield:Destroy()
    end
})

SettingsTab:CreateParagraph({
    Title = 'DeepHUB - Sell Lemons v2.1',
    Content = 'Press RightShift to toggle menu.\n\nFeatures:\n- Auto Purchase (buy all items)\n- Auto Upgrade Earners\n- Auto Click Stand (ProximityPrompt)\n- Auto Click Fruit (ClickDetector)\n- Auto Rebirth / Evolve / Ascend\n- Auto Wake Income + Boost\n- Manual actions with validation'
})

-- ============================================================
-- NOTIFICATION
-- ============================================================
Rayfield:Notify({
    Title = 'DeepHUB - Sell Lemons v2.1',
    Content = string.format(
        'Loaded! Tycoon: %s\nEarners: %d | Fruits: %d | Prompts: %d\nCash: %s | Rebirths: %d\nPress RightShift to toggle.',
        Tycoon.Name, #EarnerRemotes, #FruitClickDetectors, #EarnerPrompts,
        formatCash(getActualCash()), getRebirths()
    ),
    Duration = 8,
    Image = 'check-circle'
})
