--[[
╔══════════════════════════════════════════════════════════════╗
║          🎮 BLOX FRUITS RACE V3 SYNC - v2.0                ║
║          Đồng bộ kích hoạt V3 đa tài khoản                 ║
║          Hỗ trợ PC + Mobile (Fluxus, Delta, etc.)           ║
╚══════════════════════════════════════════════════════════════╝
]]

-- ===================== CẤU HÌNH =====================
local CONFIG = {
    API_URL    = "https://bf.banggiagp.site/bloxfruit/api.php",
    SECRET_KEY = "maycongabietgi123",
    ACC_NAME   = "",  -- Để trống = tự lấy tên Player. Hoặc đặt tên tuỳ ý như "Acc1", "Acc2"
    
    -- Timing
    POLL_TIMEOUT     = 25,
    HEARTBEAT_DELAY  = 15,
    RETRY_COUNT      = 5,
    RETRY_DELAY      = 2,
    V3_CHECK_DELAY   = 1,
    
    -- Debug
    DEBUG_MODE = false,
}

-- ===================== SERVICES =====================
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local isRunning = true
local lastTimestamp = 0
local sessionId = ""
local detectedRace = "Unknown"
local v3Activated = false

-- ===================== PLATFORM DETECTION =====================
local function detectPlatform()
    local ok1, isMobile = pcall(function()
        return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
    end)
    if ok1 and isMobile then return "Mobile" end
    
    local ok2, isConsole = pcall(function()
        return UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled
    end)
    if ok2 and isConsole then return "Console" end
    
    return "PC"
end

local Platform = detectPlatform()

-- ===================== EXECUTOR DETECTION =====================
local function detectExecutor()
    -- List các executor phổ biến
    local executors = {
        {name = "Synapse X", check = function() return syn and syn.request end},
        {name = "Script-Ware", check = function() return identifyexecutor and identifyexecutor():find("Script%-Ware") end},
        {name = "Fluxus", check = function() return (identifyexecutor and identifyexecutor():lower():find("fluxus")) or fluxus end},
        {name = "Delta", check = function() return identifyexecutor and identifyexecutor():lower():find("delta") end},
        {name = "Solara", check = function() return identifyexecutor and identifyexecutor():lower():find("solara") end},
        {name = "KRNL", check = function() return (identifyexecutor and identifyexecutor():lower():find("krnl")) or KRNL_LOADED end},
        {name = "Arceus X", check = function() return identifyexecutor and identifyexecutor():lower():find("arceus") end},
        {name = "Hydrogen", check = function() return identifyexecutor and identifyexecutor():lower():find("hydrogen") end},
        {name = "Codex", check = function() return identifyexecutor and identifyexecutor():lower():find("codex") end},
    }
    
    for _, exec in ipairs(executors) do
        local ok, result = pcall(exec.check)
        if ok and result then
            return exec.name
        end
    end
    
    -- Fallback: sử dụng identifyexecutor
    local ok, name = pcall(function()
        if identifyexecutor then return identifyexecutor() end
        if getexecutorname then return getexecutorname() end
        return nil
    end)
    if ok and name then return tostring(name) end
    
    return "Unknown"
end

local ExecutorName = detectExecutor()

-- ===================== LOGGER =====================
local LOG_PREFIX = "[V3Sync]"
local LOG_COLORS = {
    INFO  = "📘",
    OK    = "✅",
    WARN  = "⚠️",
    ERROR = "❌",
    RACE  = "🏃",
    V3    = "🚀",
    NET   = "🌐",
    HEART = "💓",
}

local function log(level, msg)
    local icon = LOG_COLORS[level] or "📝"
    local prefix = string.format("%s %s[%s]", icon, LOG_PREFIX, level)
    print(prefix, msg)
end

local function logDebug(msg)
    if CONFIG.DEBUG_MODE then
        log("INFO", "[DEBUG] " .. msg)
    end
end

-- ===================== HTTP REQUEST =====================
local function httpRequest(url, method, headers)
    method = method or "GET"
    headers = headers or {}
    
    -- Priority: syn.request > request > http.request > http_request > game:HttpGet
    local requestFunc = nil
    
    if syn and syn.request then
        requestFunc = function(u, m, h)
            local resp = syn.request({Url = u, Method = m, Headers = h})
            return resp.Body, resp.StatusCode
        end
    elseif request then
        requestFunc = function(u, m, h)
            local resp = request({Url = u, Method = m, Headers = h})
            return resp.Body, resp.StatusCode
        end
    elseif http and http.request then
        requestFunc = function(u, m, h)
            local resp = http.request({Url = u, Method = m, Headers = h})
            if type(resp) == "string" then return resp, 200 end
            return resp.Body, resp.StatusCode
        end
    elseif http_request then
        requestFunc = function(u, m, h)
            local resp = http_request({Url = u, Method = m, Headers = h})
            if type(resp) == "string" then return resp, 200 end
            return resp.Body, resp.StatusCode
        end
    elseif game and game.HttpGet then
        requestFunc = function(u)
            local body = game:HttpGet(u)
            return body, 200
        end
    end
    
    if not requestFunc then
        return nil, "No HTTP function available"
    end
    
    local ok, body, statusCode = pcall(requestFunc, url, method, headers)
    if not ok then
        return nil, "HTTP error: " .. tostring(body)
    end
    
    return body, statusCode
end

-- ===================== API CALLS =====================
local function buildUrl(action, params)
    local url = CONFIG.API_URL .. "?action=" .. action .. "&key=" .. CONFIG.SECRET_KEY
    if params then
        for k, v in pairs(params) do
            url = url .. "&" .. k .. "=" .. HttpService:UrlEncode(tostring(v))
        end
    end
    return url
end

local function apiCall(action, params, retries)
    retries = retries or CONFIG.RETRY_COUNT
    
    local url = buildUrl(action, params)
    logDebug("API Call: " .. action)
    
    for attempt = 1, retries do
        local body, err = httpRequest(url)
        
        if body then
            local ok, data = pcall(function()
                return HttpService:JSONDecode(body)
            end)
            
            if ok and data then
                if data.success then
                    return data
                else
                    log("WARN", "API returned error: " .. tostring(data.error))
                    return nil, data.error
                end
            else
                log("WARN", "JSON parse failed (attempt " .. attempt .. "): " .. tostring(body):sub(1, 100))
            end
        else
            log("WARN", "HTTP failed (attempt " .. attempt .. "): " .. tostring(err))
        end
        
        if attempt < retries then
            task.wait(CONFIG.RETRY_DELAY)
        end
    end
    
    return nil, "All " .. retries .. " attempts failed"
end

-- ===================== RACE DETECTION =====================
local RACE_DATA = {
    ["Human"]   = {v3Quest = "Human V3",   v3NPC = "Experimic",  morphId = nil},
    ["Mink"]    = {v3Quest = "Mink V3",    v3NPC = "Experimic",  morphId = nil},
    ["Fish"]    = {v3Quest = "Fish V3",    v3NPC = "Experimic",  morphId = nil},
    ["Sky"]     = {v3Quest = "Sky V3",     v3NPC = "Experimic",  morphId = nil},
    ["Ghoul"]   = {v3Quest = "Ghoul V3",   v3NPC = "Experimic",  morphId = nil},
    ["Cyborg"]  = {v3Quest = "Cyborg V3",  v3NPC = "Experimic",  morphId = nil},
    ["Angel"]   = {v3Quest = "Angel V3",   v3NPC = "Experimic",  morphId = nil},
}

local function detectRace()
    local player = LocalPlayer
    if not player then return "Unknown" end
    
    -- Phương pháp 1 (CHÍNH): Player.Data.Race [StringValue]
    -- Đã xác nhận tồn tại: Data.Race = "Ghoul" [StringValue]
    local ok1, race1 = pcall(function()
        local dataFolder = player:FindFirstChild("Data")
        if dataFolder then
            local raceVal = dataFolder:FindFirstChild("Race")
            if raceVal and raceVal:IsA("StringValue") then
                return raceVal.Value
            end
        end
        return nil
    end)
    if ok1 and race1 and race1 ~= "" then
        log("RACE", "Detect qua Data.Race: " .. race1)
        return race1
    end
    
    -- Phương pháp 2: Check GUI hiển thị tộc
    -- PlayerGui/Main/Stats/Top/Race [TextLabel] Text="Race: (Loading...)"
    local ok2, race2 = pcall(function()
        local pg = player:FindFirstChild("PlayerGui")
        if pg then
            local main = pg:FindFirstChild("Main")
            if main then
                local stats = main:FindFirstChild("Stats")
                if stats then
                    local top = stats:FindFirstChild("Top")
                    if top then
                        local raceLabel = top:FindFirstChild("Race")
                        if raceLabel and raceLabel:IsA("TextLabel") then
                            local text = raceLabel.Text
                            -- Format: "Race: Ghoul" hoặc tương tự
                            local raceName = text:match("Race:%s*(.+)")
                            if raceName and raceName ~= "(Loading...)" then
                                return raceName
                            end
                        end
                    end
                end
            end
        end
        return nil
    end)
    if ok2 and race2 and race2 ~= "" then
        log("RACE", "Detect qua GUI Stats: " .. race2)
        return race2
    end
    
    -- Phương pháp 3: Check Character Accessories
    -- Đã xác nhận: Character có GhoulAccessory [Accessory] khi tộc Ghoul
    local ok3, race3 = pcall(function()
        local char = player.Character
        if not char then return nil end
        
        local raceAccessories = {
            ["Ghoul"]  = {"GhoulAccessory"},
            ["Mink"]   = {"MinkTail", "MinkEars", "MinkAccessory"},
            ["Fish"]   = {"FishTail", "FishFins", "FishAccessory", "FishmanAccessory"},
            ["Sky"]    = {"SkyWings", "SkyAccessory", "SkypieaAccessory"},
            ["Cyborg"] = {"CyborgArm", "CyborgAccessory"},
            ["Angel"]  = {"AngelWings", "AngelAccessory", "AngelHalo"},
        }
        
        for race, indicators in pairs(raceAccessories) do
            for _, indicator in ipairs(indicators) do
                if char:FindFirstChild(indicator) then
                    return race
                end
            end
        end
        
        return "Human"
    end)
    if ok3 and race3 then
        log("RACE", "Detect qua Character Accessory: " .. race3)
        return race3
    end
    
    return "Unknown"
end

-- ===================== V3 ACTIVATOR =====================
local function isV3Active()
    local ok, result = pcall(function()
        local player = LocalPlayer
        local char = player.Character
        if not char then return false end
        
        -- Check 1 (CHÍNH): Character.RaceTransformed [BoolValue]
        -- Đã xác nhận tồn tại: Char/RaceTransformed [BoolValue] = false
        local raceTransformed = char:FindFirstChild("RaceTransformed")
        if raceTransformed and raceTransformed:IsA("BoolValue") then
            return raceTransformed.Value == true
        end
        
        -- Check 2: Character.RaceEnergy [NumberValue]
        -- Đã xác nhận: Char/RaceEnergy [NumberValue] = 0
        -- Nếu RaceEnergy > 0, có khả năng V3 đang hoạt động
        local raceEnergy = char:FindFirstChild("RaceEnergy")
        if raceEnergy and raceEnergy:IsA("NumberValue") then
            if raceEnergy.Value > 0 then
                return true
            end
        end
        
        return false
    end)
    
    return ok and result
end

local function activateV3(race)
    log("V3", "🔥 Bắt đầu kích hoạt V3 cho tộc: " .. race)
    
    -- Gửi log bắt đầu
    pcall(function()
        apiCall("log", {acc = CONFIG.ACC_NAME, s = "v3_start", race = race, detail = "Bắt đầu kích hoạt V3"}, 1)
    end)
    
    local success = false
    local player = Players.LocalPlayer
    
    --[[
        PHÂN TÍCH CẤU TRÚC GAME:
        - Char/RaceAbility [LocalScript] → Script xử lý kỹ năng tộc trên client
        - Char/RaceTransformed [BoolValue] = false → Trạng thái biến hình tộc
        - Char/RaceEnergy [NumberValue] = 0 → Năng lượng tộc 
        - RS/Events/UsedRaceSkill [RemoteEvent] → CHỈ dùng để BÁO (notification), KHÔNG phải kích hoạt
        - PlayerGui/MobileContextButtons/.../BoundActionRaceAbility → Nút tộc trên Mobile
        
        Race V3 kích hoạt qua ContextActionService bind "RaceAbility" (phím T)
        → LocalScript "RaceAbility" trong Character xử lý logic
        
        VirtualInputManager BỊ BLOCK, phải dùng:
        1. getsenv() để truy cập hàm bên trong RaceAbility script
        2. keypress/keyrelease cấp executor (Delta, Fluxus hỗ trợ)
        3. getconnections trên nút Mobile
    ]]
    
    -- ═══════════════════════════════════════════════════════
    -- Cách 1 (CHÍNH): getsenv - Gọi trực tiếp hàm trong RaceAbility LocalScript
    -- ═══════════════════════════════════════════════════════
    pcall(function()
        local char = player.Character
        if not char then return end
        
        local raceScript = char:FindFirstChild("RaceAbility")
        if not raceScript then 
            log("WARN", "[1] Không tìm thấy RaceAbility script trong Character")
            return 
        end
        
        -- getsenv: lấy script environment (Delta, Fluxus, Synapse đều hỗ trợ)
        if not getsenv then
            log("WARN", "[1] Executor không hỗ trợ getsenv")
            return
        end
        
        log("V3", "[1] Truy cập RaceAbility script environment...")
        local env = getsenv(raceScript)
        
        -- Tìm hàm kích hoạt trong environment
        -- Thường tên là activate, toggle, use, transform, v.v.
        local activationKeywords = {
            "activate", "toggle", "transform", "use", "race", 
            "ability", "awaken", "v3", "skill"
        }
        
        -- Duyệt qua tất cả function trong environment
        for name, value in pairs(env) do
            if type(value) == "function" then
                local nameLower = tostring(name):lower()
                for _, keyword in ipairs(activationKeywords) do
                    if nameLower:find(keyword) then
                        log("V3", "[1] Tìm thấy hàm: " .. tostring(name) .. " → Gọi thử...")
                        pcall(value)
                        task.wait(0.5)
                        if isV3Active() then
                            success = true
                            log("OK", "✅ V3 kích hoạt qua getsenv." .. tostring(name) .. "()")
                            return
                        end
                    end
                end
            end
        end
        
        -- Nếu không tìm thấy qua tên, thử tìm qua upvalue của connections
        if not success and getconnections then
            log("V3", "[1b] Tìm qua ContextActionService callback...")
            local CAS = game:GetService("ContextActionService")
            -- Lấy callback function đã bind cho RaceAbility
            local boundInfo = CAS:GetAllBoundActionInfo()
            for actionName, _ in pairs(boundInfo) do
                if actionName:lower():find("race") then
                    log("V3", "[1b] Tìm thấy bound action: " .. actionName)
                    -- Gọi CallFunction nếu có
                    pcall(function()
                        CAS:CallFunction(actionName, Enum.UserInputState.Begin, 
                            Instance.new("InputObject"))
                    end)
                    task.wait(0.5)
                    if isV3Active() then
                        success = true
                        log("OK", "✅ V3 kích hoạt qua CAS:CallFunction!")
                        return
                    end
                end
            end
        end
    end)
    
    task.wait(1.5)
    if isV3Active() then
        success = true
    end
    
    -- ═══════════════════════════════════════════════════════
    -- Cách 2: keypress/keyrelease cấp executor (KHÔNG dùng VirtualInputManager)
    -- Delta, Fluxus, Synapse đều có hàm này ở global scope
    -- ═══════════════════════════════════════════════════════
    if not success then
        pcall(function()
            if keypress then
                log("V3", "[2] Dùng keypress executor-level (phím T)...")
                keypress(0x54) -- T key (VK code)
                task.wait(0.15)
                if keyrelease then
                    keyrelease(0x54)
                end
            elseif Input and Input.KeyPress then
                log("V3", "[2] Dùng Input.KeyPress (phím T)...")
                Input.KeyPress(0x54)
                task.wait(0.15)
                Input.KeyRelease(0x54)
            else
                log("WARN", "[2] Executor không hỗ trợ keypress")
                return
            end
        end)
        
        task.wait(1.5)
        if isV3Active() then
            success = true
            log("OK", "✅ V3 kích hoạt thành công qua keypress!")
        end
    end
    
    -- ═══════════════════════════════════════════════════════
    -- Cách 3: getconnections trên nút Mobile BoundActionRaceAbility
    -- ═══════════════════════════════════════════════════════
    if not success then
        pcall(function()
            local pg = player:FindFirstChild("PlayerGui")
            if not pg then return end
            
            local mobileBtn = pg:FindFirstChild("MobileContextButtons")
            if not mobileBtn then return end
            
            local ctxFrame = mobileBtn:FindFirstChild("ContextButtonFrame")
            if not ctxFrame then return end
            
            local raceAbilityBtn = ctxFrame:FindFirstChild("BoundActionRaceAbility")
            if not raceAbilityBtn then 
                log("WARN", "[3] Không tìm thấy BoundActionRaceAbility")
                return 
            end
            
            log("V3", "[3] Fire connections nút RaceAbility Mobile...")
            
            -- Tìm tất cả button/input bên trong CanvasGroup
            local buttons = {}
            for _, desc in ipairs(raceAbilityBtn:GetDescendants()) do
                if desc:IsA("GuiButton") then
                    table.insert(buttons, desc)
                end
            end
            
            local totalFired = 0
            for _, btn in ipairs(buttons) do
                if getconnections then
                    -- Fire Activated signal (cách game xử lý click)
                    local conns = getconnections(btn.Activated)
                    for _, conn in ipairs(conns) do
                        pcall(function() conn:Fire() end)
                        totalFired = totalFired + 1
                    end
                    -- Cũng thử MouseButton1Click
                    conns = getconnections(btn.MouseButton1Click)
                    for _, conn in ipairs(conns) do
                        pcall(function() conn:Fire() end)
                        totalFired = totalFired + 1
                    end
                elseif firesignal then
                    firesignal(btn.Activated)
                    firesignal(btn.MouseButton1Click)
                    totalFired = totalFired + 2
                end
            end
            
            log("V3", "[3] Đã fire " .. totalFired .. " connections từ " .. #buttons .. " buttons")
        end)
        
        task.wait(1.5)
        if isV3Active() then
            success = true
            log("OK", "✅ V3 kích hoạt thành công qua nút Mobile!")
        end
    end
    
    -- ═══════════════════════════════════════════════════════
    -- Cách 4: Hook trực tiếp ContextActionService callback
    -- ═══════════════════════════════════════════════════════
    if not success then
        pcall(function()
            if not getrawmetatable then
                log("WARN", "[4] Executor không hỗ trợ getrawmetatable")
                return
            end
            
            log("V3", "[4] Tìm callback trong ContextActionService...")
            local CAS = game:GetService("ContextActionService")
            
            -- Thử tạo InputObject giả
            local fakeInput = Instance.new("InputObject")
            -- Enum.UserInputType.Keyboard, KeyCode = T
            
            -- Duyệt tìm trong registered callbacks
            local boundActions = CAS:GetAllBoundActionInfo()
            for actionName, info in pairs(boundActions) do
                local nameLower = actionName:lower()
                if nameLower:find("race") or nameLower == "raceability" then
                    log("V3", "[4] Found: " .. actionName)
                    
                    -- Thử gọi qua nhiều cách
                    -- A) CallFunction (một số executor hỗ trợ)
                    pcall(function()
                        CAS:CallFunction(actionName, Enum.UserInputState.Begin)
                    end)
                    task.wait(0.3)
                    
                    -- B) Nếu có getboundfunction 
                    if getboundfunction then
                        pcall(function()
                            local func = getboundfunction(CAS, actionName)
                            if func then
                                func(actionName, Enum.UserInputState.Begin, fakeInput)
                            end
                        end)
                    end
                    
                    break
                end
            end
        end)
        
        task.wait(1.5)
        if isV3Active() then
            success = true
            log("OK", "✅ V3 kích hoạt thành công qua CAS hook!")
        end
    end
    
    -- ═══════════════════════════════════════════════════════
    -- Final check - chờ thêm rồi check lần cuối
    -- ═══════════════════════════════════════════════════════
    if not success then
        task.wait(2)
        if isV3Active() then
            success = true
            log("OK", "✅ V3 xác nhận đã kích hoạt (delayed check)!")
        end
    end
    
    -- Gửi log kết quả
    pcall(function()
        local verified = isV3Active()
        local status = verified and "v3_done" or "v3_attempted"
        apiCall("log", {
            acc = CONFIG.ACC_NAME, 
            s = status, 
            race = race, 
            detail = verified 
                and "✅ V3 kích hoạt + xác nhận RaceTransformed=true" 
                or "⚠️ Đã thử 4 cách nhưng RaceTransformed vẫn false"
        }, 1)
    end)
    
    return success
end

-- ===================== V3 DETECTION (HOST) =====================
local function checkHostV3()
    -- Check xem host đã bật V3 trong game chưa
    return isV3Active()
end

-- ===================== GUI =====================
local function createGUI()
    -- Xóa GUI cũ nếu có
    pcall(function()
        local existing = CoreGui:FindFirstChild("V3SyncGUI")
        if existing then existing:Destroy() end
    end)
    pcall(function()
        local existing = LocalPlayer.PlayerGui:FindFirstChild("V3SyncGUI")
        if existing then existing:Destroy() end
    end)
    
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "V3SyncGUI"
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    
    -- Thử CoreGui trước, fallback PlayerGui
    pcall(function() screenGui.Parent = CoreGui end)
    if not screenGui.Parent then
        screenGui.Parent = LocalPlayer.PlayerGui
    end
    
    -- ===== Main Frame =====
    local mainFrame = Instance.new("Frame")
    mainFrame.Name = "MainFrame"
    mainFrame.Size = UDim2.new(0, 320, 0, 200)
    mainFrame.Position = UDim2.new(0, 15, 0.5, -100)
    mainFrame.BackgroundColor3 = Color3.fromRGB(15, 15, 25)
    mainFrame.BackgroundTransparency = 0.08
    mainFrame.BorderSizePixel = 0
    mainFrame.Parent = screenGui
    mainFrame.Active = true
    mainFrame.Draggable = true
    
    local mainCorner = Instance.new("UICorner")
    mainCorner.CornerRadius = UDim.new(0, 12)
    mainCorner.Parent = mainFrame
    
    local mainStroke = Instance.new("UIStroke")
    mainStroke.Color = Color3.fromRGB(200, 150, 255)
    mainStroke.Thickness = 1.5
    mainStroke.Transparency = 0.3
    mainStroke.Parent = mainFrame
    
    -- ===== Header =====
    local header = Instance.new("Frame")
    header.Name = "Header"
    header.Size = UDim2.new(1, 0, 0, 40)
    header.BackgroundColor3 = Color3.fromRGB(25, 15, 40)
    header.BackgroundTransparency = 0.3
    header.BorderSizePixel = 0
    header.Parent = mainFrame
    
    local headerCorner = Instance.new("UICorner")
    headerCorner.CornerRadius = UDim.new(0, 12)
    headerCorner.Parent = header
    
    -- Fix bottom corner
    local headerFix = Instance.new("Frame")
    headerFix.Size = UDim2.new(1, 0, 0, 12)
    headerFix.Position = UDim2.new(0, 0, 1, -12)
    headerFix.BackgroundColor3 = header.BackgroundColor3
    headerFix.BackgroundTransparency = header.BackgroundTransparency
    headerFix.BorderSizePixel = 0
    headerFix.Parent = header
    
    local titleLabel = Instance.new("TextLabel")
    titleLabel.Name = "Title"
    titleLabel.Size = UDim2.new(1, -60, 1, 0)
    titleLabel.Position = UDim2.new(0, 12, 0, 0)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text = "🎮 V3 SYNC [" .. CONFIG.ACC_NAME .. "]"
    titleLabel.TextColor3 = Color3.fromRGB(200, 170, 255)
    titleLabel.TextSize = 15
    titleLabel.Font = Enum.Font.GothamBold
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.Parent = header
    
    -- Close button
    local closeBtn = Instance.new("TextButton")
    closeBtn.Name = "CloseBtn"
    closeBtn.Size = UDim2.new(0, 28, 0, 28)
    closeBtn.Position = UDim2.new(1, -36, 0, 6)
    closeBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
    closeBtn.BackgroundTransparency = 0.5
    closeBtn.Text = "✕"
    closeBtn.TextColor3 = Color3.fromRGB(255, 150, 150)
    closeBtn.TextSize = 14
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.BorderSizePixel = 0
    closeBtn.Parent = header
    
    local closeBtnCorner = Instance.new("UICorner")
    closeBtnCorner.CornerRadius = UDim.new(0, 6)
    closeBtnCorner.Parent = closeBtn
    
    closeBtn.MouseButton1Click:Connect(function()
        isRunning = false
        log("INFO", "Script dừng bởi người dùng")
        screenGui:Destroy()
    end)
    
    -- ===== Content Area =====
    local content = Instance.new("Frame")
    content.Name = "Content"
    content.Size = UDim2.new(1, -20, 1, -50)
    content.Position = UDim2.new(0, 10, 0, 45)
    content.BackgroundTransparency = 1
    content.Parent = mainFrame
    
    -- Status Label
    local statusLabel = Instance.new("TextLabel")
    statusLabel.Name = "StatusLabel"
    statusLabel.Size = UDim2.new(1, 0, 0, 18)
    statusLabel.Position = UDim2.new(0, 0, 0, 0)
    statusLabel.BackgroundTransparency = 1
    statusLabel.Text = "⏳ Đang khởi tạo..."
    statusLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
    statusLabel.TextSize = 13
    statusLabel.Font = Enum.Font.Gotham
    statusLabel.TextXAlignment = Enum.TextXAlignment.Left
    statusLabel.TextWrapped = true
    statusLabel.Parent = content
    
    -- Info labels
    local function createInfoLabel(name, yPos, text)
        local label = Instance.new("TextLabel")
        label.Name = name
        label.Size = UDim2.new(1, 0, 0, 16)
        label.Position = UDim2.new(0, 0, 0, yPos)
        label.BackgroundTransparency = 1
        label.Text = text
        label.TextColor3 = Color3.fromRGB(160, 160, 170)
        label.TextSize = 11
        label.Font = Enum.Font.Gotham
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.TextWrapped = true
        label.Parent = content
        return label
    end
    
    local raceLabel    = createInfoLabel("RaceLabel", 22, "🏃 Tộc: Đang detect...")
    local platformLabel = createInfoLabel("PlatformLabel", 40, "💻 " .. Platform .. " | " .. ExecutorName)
    local accLabel     = createInfoLabel("AccLabel", 58, "👤 " .. CONFIG.ACC_NAME)
    local onlineLabel  = createInfoLabel("OnlineLabel", 76, "🌐 Online: ...")
    
    -- Log text
    local logFrame = Instance.new("Frame")
    logFrame.Name = "LogFrame"
    logFrame.Size = UDim2.new(1, 0, 0, 45)
    logFrame.Position = UDim2.new(0, 0, 1, -80)
    logFrame.BackgroundColor3 = Color3.fromRGB(5, 5, 15)
    logFrame.BackgroundTransparency = 0.3
    logFrame.BorderSizePixel = 0
    logFrame.Parent = content
    
    local logCorner = Instance.new("UICorner")
    logCorner.CornerRadius = UDim.new(0, 6)
    logCorner.Parent = logFrame
    
    local logLabel = Instance.new("TextLabel")
    logLabel.Name = "LogLabel"
    logLabel.Size = UDim2.new(1, -10, 1, -6)
    logLabel.Position = UDim2.new(0, 5, 0, 3)
    logLabel.BackgroundTransparency = 1
    logLabel.Text = "📋 Chờ tín hiệu..."
    logLabel.TextColor3 = Color3.fromRGB(140, 140, 150)
    logLabel.TextSize = 10
    logLabel.Font = Enum.Font.Code
    logLabel.TextXAlignment = Enum.TextXAlignment.Left
    logLabel.TextYAlignment = Enum.TextYAlignment.Top
    logLabel.TextWrapped = true
    logLabel.Parent = logFrame
    
    -- Nút gửi tín hiệu thủ công (tất cả acc đều có)
    local sendBtn = Instance.new("TextButton")
    sendBtn.Name = "SendBtn"
    sendBtn.Size = UDim2.new(1, 0, 0, 32)
    sendBtn.Position = UDim2.new(0, 0, 1, -30)
    sendBtn.BackgroundColor3 = Color3.fromRGB(40, 120, 60)
    sendBtn.Text = "🚀 GỬI TÍN HIỆU V3"
    sendBtn.TextColor3 = Color3.fromRGB(200, 255, 200)
    sendBtn.TextSize = 13
    sendBtn.Font = Enum.Font.GothamBold
    sendBtn.BorderSizePixel = 0
    sendBtn.Parent = content
    
    local sendBtnCorner = Instance.new("UICorner")
    sendBtnCorner.CornerRadius = UDim.new(0, 8)
    sendBtnCorner.Parent = sendBtn
    
    sendBtn.MouseButton1Click:Connect(function()
        sendBtn.Text = "⏳ Đang gửi..."
        sendBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
        
        local data = apiCall("set", {
            status = "true",
            host = CONFIG.ACC_NAME,
            race = detectedRace,
            msg = "Manual trigger by " .. CONFIG.ACC_NAME,
        })
        
        if data then
            sendBtn.Text = "✅ ĐÃ GỬI!"
            sendBtn.BackgroundColor3 = Color3.fromRGB(30, 150, 50)
            log("OK", "Đã gửi tín hiệu V3 thủ công!")
            sessionId = data.session_id or ""
        else
            sendBtn.Text = "❌ LỖI - THỬ LẠI"
            sendBtn.BackgroundColor3 = Color3.fromRGB(150, 40, 40)
        end
        
        task.wait(3)
        if sendBtn and sendBtn.Parent then
            sendBtn.Text = "🚀 GỬI TÍN HIỆU V3"
            sendBtn.BackgroundColor3 = Color3.fromRGB(40, 120, 60)
        end
    end)
    
    return {
        gui = screenGui,
        statusLabel = statusLabel,
        raceLabel = raceLabel,
        platformLabel = platformLabel,
        accLabel = accLabel,
        onlineLabel = onlineLabel,
        logLabel = logLabel,
        sendBtn = sendBtn,
        mainFrame = mainFrame,
    }
end

-- ===================== UPDATE GUI =====================
local function updateGUI(gui, updates)
    if not gui or not gui.gui or not gui.gui.Parent then return end
    
    pcall(function()
        if updates.status then
            gui.statusLabel.Text = updates.status
        end
        if updates.statusColor then
            gui.statusLabel.TextColor3 = updates.statusColor
        end
        if updates.race then
            gui.raceLabel.Text = "🏃 Tộc: " .. updates.race
        end
        if updates.online then
            gui.onlineLabel.Text = "🌐 Online: " .. tostring(updates.online) .. " acc"
        end
        if updates.log then
            gui.logLabel.Text = updates.log
        end
    end)
end

-- ===================== HEARTBEAT LOOP =====================
local function startHeartbeat(gui)
    task.spawn(function()
        while isRunning do
            pcall(function()
                local data = apiCall("heartbeat", {
                    acc = CONFIG.ACC_NAME,
                    host = "1",
                    race = detectedRace,
                    platform = Platform,
                }, 1)
                
                if data and data.online_count then
                    updateGUI(gui, {online = data.online_count})
                end
            end)
            
            task.wait(CONFIG.HEARTBEAT_DELAY)
        end
    end)
end

-- ===================== UNIFIED MODE =====================
-- Mỗi acc vừa theo dõi V3 của mình, vừa lắng nghe tín hiệu từ acc khác
local function runUnified(gui)
    log("V3", "🔄 Chế độ UNIFIED - Vừa theo dõi V3 + vừa nhận tín hiệu")
    updateGUI(gui, {
        status = "🔄 Đang theo dõi V3 + lắng nghe tín hiệu...",
        statusColor = Color3.fromRGB(200, 170, 255),
    })
    
    local alreadySentThisSession = false
    local lastActivatedByMe = false -- đánh dấu: V3 này do MÌNH bật hay nhận tín hiệu
    
    -- ============ THREAD 1: Theo dõi V3 của mình ============
    -- Nếu mình bật V3 (nhấn T thủ công) → gửi tín hiệu cho acc khác
    task.spawn(function()
        while isRunning do
            pcall(function()
                local v3Active = isV3Active()
                
                if v3Active and not alreadySentThisSession then
                    -- Mình vừa bật V3 → gửi tín hiệu
                    alreadySentThisSession = true
                    lastActivatedByMe = true
                    
                    log("V3", "🔥 V3 của mình đã bật! Gửi tín hiệu cho các acc khác...")
                    updateGUI(gui, {
                        status = "🔥 V3 BẬt! Gửi tín hiệu...",
                        statusColor = Color3.fromRGB(255, 180, 50),
                        log = "📡 Gửi tín hiệu V3 cho tất cả acc...",
                    })
                    
                    local data = apiCall("set", {
                        status = "true",
                        host = CONFIG.ACC_NAME,
                        race = detectedRace,
                        msg = "V3 bật bởi " .. CONFIG.ACC_NAME,
                    })
                    
                    if data then
                        sessionId = data.session_id or ""
                        log("OK", "✅ Đã gửi tín hiệu V3!")
                        updateGUI(gui, {
                            status = "✅ V3 bật + đã gửi tín hiệu!",
                            statusColor = Color3.fromRGB(50, 255, 100),
                            log = "✅ V3 " .. detectedRace .. " bật thành công!\n📡 Acc khác đang nhận tín hiệu...",
                        })
                    end
                    
                elseif not v3Active and alreadySentThisSession and lastActivatedByMe then
                    -- V3 tắt → reset
                    alreadySentThisSession = false
                    lastActivatedByMe = false
                    pcall(function()
                        apiCall("set", {status = "false", host = CONFIG.ACC_NAME}, 1)
                    end)
                    updateGUI(gui, {
                        status = "🔄 Đang theo dõi V3 + lắng nghe tín hiệu...",
                        statusColor = Color3.fromRGB(200, 170, 255),
                        log = "🔄 V3 đã tắt, chờ kích hoạt lại...",
                    })
                end
            end)
            
            task.wait(CONFIG.V3_CHECK_DELAY)
        end
    end)
    
    -- ============ THREAD 2: Lắng nghe tín hiệu từ API ============
    -- Nếu acc khác bật V3 → tự bật V3 của mình
    task.spawn(function()
        -- Lấy timestamp hiện tại
        pcall(function()
            local data = apiCall("ping", {})
            if data and data.server_time then
                lastTimestamp = tonumber(data.server_time) or 0
            end
        end)
        
        while isRunning do
            local data = apiCall("get", {last = tostring(lastTimestamp), timeout = tostring(CONFIG.POLL_TIMEOUT)}, 2)
            
            if data then
                if not data.timeout then
                    lastTimestamp = tonumber(data.updated_at) or lastTimestamp
                    
                    if data.status == true then
                        local hostName = data.host_name or "Unknown"
                        
                        -- Chỉ kích hoạt nếu tín hiệu từ ACC KHÁC (không phải mình gửi)
                        if hostName ~= CONFIG.ACC_NAME and not isV3Active() then
                            local hostRace = data.host_race or ""
                            sessionId = data.session_id or ""
                            
                            log("OK", "🎉 NHẬN TÍN HIỆU V3 từ: " .. hostName)
                            updateGUI(gui, {
                                status = "🔥 Nhận tín hiệu V3 từ " .. hostName .. "!",
                                statusColor = Color3.fromRGB(255, 200, 50),
                                log = "📡 Từ: " .. hostName .. " | Tộc: " .. hostRace .. "\n⏰ Đang kích hoạt V3...",
                            })
                            
                            -- Kích hoạt V3
                            local success = activateV3(detectedRace)
                            alreadySentThisSession = true
                            lastActivatedByMe = false -- không phải mình bật
                            
                            if success then
                                v3Activated = true
                                updateGUI(gui, {
                                    status = "✅ V3 " .. detectedRace .. " đã kích hoạt!",
                                    statusColor = Color3.fromRGB(50, 255, 100),
                                    log = "✅ " .. CONFIG.ACC_NAME .. " bật " .. detectedRace .. " V3 thành công!",
                                })
                            else
                                updateGUI(gui, {
                                    status = "⚠️ V3 có thể chưa kích hoạt",
                                    statusColor = Color3.fromRGB(255, 200, 80),
                                    log = "⚠️ Thử kích hoạt V3 xong\nKiểm tra game xem V3 đã bật chưa",
                                })
                            end
                            
                            task.wait(5)
                        end
                    else
                        -- Status = false (reset từ acc khác)
                        if v3Activated and not lastActivatedByMe then
                            v3Activated = false
                            alreadySentThisSession = false
                            updateGUI(gui, {
                                status = "🔄 Đang theo dõi V3 + lắng nghe tín hiệu...",
                                statusColor = Color3.fromRGB(200, 170, 255),
                                log = "🔄 Đã reset. Chờ tín hiệu mới...",
                            })
                        end
                    end
                else
                    lastTimestamp = tonumber(data.updated_at) or lastTimestamp
                    logDebug("Long poll timeout, continue...")
                end
            else
                log("ERROR", "Lỗi kết nối API, thử lại...")
                updateGUI(gui, {
                    status = "❌ Mất kết nối API...",
                    statusColor = Color3.fromRGB(255, 100, 100),
                })
                task.wait(CONFIG.RETRY_DELAY)
            end
        end
    end)
    
    -- Chờ cho đến khi script dừng
    while isRunning do
        task.wait(1)
    end
end

-- ===================== MAIN =====================
local function main()
    -- Auto-detect ACC_NAME nếu để trống
    if CONFIG.ACC_NAME == "" then
        CONFIG.ACC_NAME = LocalPlayer.Name
    end
    
    log("INFO", "═══════════════════════════════════════")
    log("INFO", "  🎮 Blox Fruits V3 Sync v3.0")
    log("INFO", "  Mode: UNIFIED (Host + Client)")
    log("INFO", "  Account: " .. CONFIG.ACC_NAME)
    log("INFO", "  Platform: " .. Platform)
    log("INFO", "  Executor: " .. ExecutorName)
    log("INFO", "═══════════════════════════════════════")
    
    -- Test API connection
    log("NET", "Kiểm tra kết nối API...")
    local pingData = apiCall("ping", {})
    
    if not pingData then
        log("ERROR", "❌ KHÔNG THỂ KẾT NỐI API!")
        log("ERROR", "Kiểm tra: 1) URL API  2) SECRET_KEY  3) Internet")
        warn("[V3Sync] FATAL: Cannot connect to API. Script stopped.")
        return
    end
    
    log("OK", "✅ API connected! Server version: " .. (pingData.version or "?"))
    
    -- Detect race
    log("RACE", "Đang detect tộc...")
    detectedRace = detectRace()
    log("RACE", "Tộc phát hiện: " .. detectedRace)
    
    -- Create GUI
    local gui = createGUI()
    updateGUI(gui, {
        race = detectedRace,
    })
    
    -- Start heartbeat
    startHeartbeat(gui)
    
    -- Gửi log connect
    pcall(function()
        apiCall("log", {
            acc = CONFIG.ACC_NAME,
            s = "connected",
            race = detectedRace,
            detail = Platform .. " | " .. ExecutorName,
        }, 1)
    end)
    
    -- Run unified mode
    runUnified(gui)
    
    log("INFO", "Script đã dừng.")
end

-- ===================== START =====================
local ok, err = pcall(main)
if not ok then
    warn("[V3Sync] FATAL ERROR:", err)
end
