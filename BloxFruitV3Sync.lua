--[[
╔══════════════════════════════════════════════════════════════╗
║     BLOX FRUITS RACE V3 SYNC - AUTO MODE                    ║
║     Đồng bộ Race V3 giữa nhiều tài khoản                    ║
║     ✅ KHÔNG CẦN CONFIG - CHẠY LÀ DÙNG                      ║
║     ✅ HỖ TRỢ CẢ PC VÀ MOBILE                               ║
║                                                              ║
║     Cơ chế: Acc nào bật V3 trước → tự gửi tín hiệu          ║
║             Các acc còn lại → tự nhận và bật V3 theo         ║
╚══════════════════════════════════════════════════════════════╝

Hướng dẫn:
  CHỈ CẦN SỬA 2 DÒNG BÊN DƯỚI (API_URL và SECRET_KEY)
  KHÔNG CẦN SỬA GÌ KHÁC - CHẠY GIỐNG NHAU TRÊN MỌI ACC
]]

-- ╔══════════════════════════════════════════════════════════╗
-- ║  CẤU HÌNH - CHỈ CẦN SỬA 2 DÒNG NÀY                   ║
-- ╚══════════════════════════════════════════════════════════╝

local API_URL    = "https://bf.banggiagp.site/bloxfruit/api.php"
local SECRET_KEY = "maycongabietgi123"

-- ═══ KHÔNG CẦN SỬA GÌ BÊN DƯỚI ═══


-- ╔══════════════════════════════════════════════════════════╗
-- ║  SERVICES + AUTO DETECT                                 ║
-- ╚══════════════════════════════════════════════════════════╝

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
local HumanoidRootPart = Character:WaitForChild("HumanoidRootPart")
local Humanoid = Character:WaitForChild("Humanoid")

-- Tự động lấy tên acc từ Roblox (không cần config)
local ACC_NAME = LocalPlayer.Name

-- Detect PC hay Mobile
local IS_MOBILE = false
pcall(function()
    IS_MOBILE = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end)

-- Detect executor
local EXECUTOR_NAME = "Unknown"
pcall(function()
    if syn then EXECUTOR_NAME = "Synapse X"
    elseif KRNL_LOADED then EXECUTOR_NAME = "KRNL"
    elseif fluxus then EXECUTOR_NAME = "Fluxus"
    elseif Solara then EXECUTOR_NAME = "Solara"
    elseif arceus then EXECUTOR_NAME = "Arceus X"
    elseif Hydrogen then EXECUTOR_NAME = "Hydrogen"
    elseif Delta then EXECUTOR_NAME = "Delta"
    elseif Codex then EXECUTOR_NAME = "Codex"
    elseif getexecutorname then EXECUTOR_NAME = getexecutorname()
    elseif identifyexecutor then EXECUTOR_NAME = identifyexecutor()
    end
end)

-- Trạng thái
local g_isRunning = true
local g_currentRace = "Unknown"
local g_lastTimestamp = 0
local g_connectionOK = false
local g_myV3WasOff = true       -- V3 của mình đang TẮT (chờ bật)
local g_alreadyActivated = false -- Đã nhận tín hiệu và bật V3 rồi (tránh lặp)

-- Cập nhật Character khi respawn
LocalPlayer.CharacterAdded:Connect(function(char)
    Character = char
    HumanoidRootPart = char:WaitForChild("HumanoidRootPart")
    Humanoid = char:WaitForChild("Humanoid")
end)

-- Log
local function Log(level, msg)
    local prefix = ({
        INFO  = "[V3Sync][INFO] ",
        WARN  = "[V3Sync][WARN] ",
        ERROR = "[V3Sync][ERR]  ",
        OK    = "[V3Sync][OK]   ",
    })[level] or "[V3Sync] "
    print(prefix .. tostring(msg))
end

local function SafeWait(seconds)
    local start = tick()
    while (tick() - start) < seconds and g_isRunning do
        task.wait(0.1)
    end
end

Log("INFO", "Account: " .. ACC_NAME)
Log("INFO", "Platform: " .. (IS_MOBILE and "Mobile" or "PC") .. " | " .. EXECUTOR_NAME)


-- ╔══════════════════════════════════════════════════════════╗
-- ║  HTTP HELPER (PC + Mobile)                              ║
-- ╚══════════════════════════════════════════════════════════╝

local HttpHelper = {}

local function getHttpFunc()
    if syn and syn.request then
        return function(url)
            return syn.request({ Url = url, Method = "GET" }).Body
        end
    end
    if request then
        return function(url)
            return request({ Url = url, Method = "GET" }).Body
        end
    end
    if http and http.request then
        return function(url)
            return http.request({ Url = url, Method = "GET" }).Body
        end
    end
    if http_request then
        return function(url)
            return http_request({ Url = url, Method = "GET" }).Body
        end
    end
    if HttpPost or HttpGet then
        return function(url)
            if HttpGet then return HttpGet(url) end
        end
    end
    pcall(function()
        if game.HttpGet then
            return function(url) return game:HttpGet(url) end
        end
    end)
    if HttpService then
        return function(url) return HttpService:GetAsync(url) end
    end
    return nil
end

local httpFunc = getHttpFunc()

if not httpFunc then
    Log("ERROR", "Executor không hỗ trợ HTTP!")
    pcall(function()
        local sg = Instance.new("ScreenGui")
        sg.Parent = CoreGui
        local lb = Instance.new("TextLabel")
        lb.Size = UDim2.new(0.8, 0, 0, 50)
        lb.Position = UDim2.new(0.1, 0, 0.4, 0)
        lb.BackgroundColor3 = Color3.fromRGB(200, 30, 30)
        lb.TextColor3 = Color3.new(1, 1, 1)
        lb.Text = "❌ Executor không hỗ trợ HTTP!"
        lb.TextSize = IS_MOBILE and 12 or 16
        lb.TextWrapped = true
        lb.Font = Enum.Font.GothamBold
        lb.Parent = sg
        Instance.new("UICorner", lb).CornerRadius = UDim.new(0, 10)
    end)
    return
end

function HttpHelper.Request(url, maxRetry)
    maxRetry = maxRetry or 3
    for attempt = 1, maxRetry do
        local ok, result = pcall(function() return httpFunc(url) end)
        if ok and result then
            local pOK, data = pcall(function() return HttpService:JSONDecode(result) end)
            if pOK and data then
                g_connectionOK = true
                return data
            end
        end
        if attempt < maxRetry then task.wait(0.5 * attempt) end
    end
    g_connectionOK = false
    return nil
end

function HttpHelper.BuildURL(action, params)
    local url = API_URL .. "?action=" .. action .. "&key=" .. SECRET_KEY
    if params then
        for k, v in pairs(params) do
            local enc = tostring(v)
            pcall(function() enc = HttpService:UrlEncode(tostring(v)) end)
            url = url .. "&" .. tostring(k) .. "=" .. enc
        end
    end
    return url
end


-- ╔══════════════════════════════════════════════════════════╗
-- ║  RACE DETECTOR                                          ║
-- ╚══════════════════════════════════════════════════════════╝

local RaceDetector = {}

function RaceDetector.GetCurrentRace()
    local race = "Human"
    local ok, result = pcall(function()
        local plrData = LocalPlayer:FindFirstChild("Data")
            or LocalPlayer:FindFirstChild("Stats")
            or LocalPlayer:FindFirstChild("PlayerData")
        if plrData then
            local rv = plrData:FindFirstChild("Race")
            if rv then return tostring(rv.Value) end
        end
        for _, f in pairs(LocalPlayer:GetChildren()) do
            if f:IsA("Folder") or f:IsA("Configuration") then
                local rc = f:FindFirstChild("Race")
                if rc then return tostring(rc.Value) end
            end
        end
        local dr = LocalPlayer:FindFirstChild("Race")
        if dr then return tostring(dr.Value) end
        local pdf = ReplicatedStorage:FindFirstChild("PlayerData")
        if pdf then
            local md = pdf:FindFirstChild(LocalPlayer.Name)
            if md then
                local rv = md:FindFirstChild("Race")
                if rv then return tostring(rv.Value) end
            end
        end
        return "Human"
    end)
    if ok then race = result end

    local map = {
        human="Human", mink="Mink", fish="Fishman", fishman="Fishman",
        shark="Fishman", sky="Skypiean", skypiean="Skypiean",
        angel="Angel", ghoul="Ghoul", cyborg="Cyborg"
    }
    race = map[string.lower(race)] or race
    g_currentRace = race
    return race
end

function RaceDetector.HasV3()
    local hasV3 = false
    pcall(function()
        local plrData = LocalPlayer:FindFirstChild("Data")
            or LocalPlayer:FindFirstChild("Stats")
            or LocalPlayer:FindFirstChild("PlayerData")
        if plrData then
            local v = plrData:FindFirstChild("RaceV3")
                or plrData:FindFirstChild("V3")
                or plrData:FindFirstChild("HasV3")
                or plrData:FindFirstChild("RaceAwakening")
            if v then hasV3 = (v.Value == true or v.Value == 1 or v.Value == "true") end
        end
        if not hasV3 then
            local pdf = ReplicatedStorage:FindFirstChild("PlayerData")
            if pdf then
                local md = pdf:FindFirstChild(LocalPlayer.Name)
                if md then
                    local v = md:FindFirstChild("RaceV3") or md:FindFirstChild("V3") or md:FindFirstChild("HasV3")
                    if v then hasV3 = (v.Value == true or v.Value == 1) end
                end
            end
        end
    end)
    return hasV3
end


-- ╔══════════════════════════════════════════════════════════╗
-- ║  V3 ACTIVATOR                                           ║
-- ╚══════════════════════════════════════════════════════════╝

local V3Activator = {}

local function FireRaceV3Remote()
    pcall(function()
        local remotes = {"RaceAwakening","AwakeRace","RaceV3","ActivateV3","RaceTransform","Awaken"}
        for _, name in pairs(remotes) do
            local r = ReplicatedStorage:FindFirstChild(name, true)
            if r then
                if r:IsA("RemoteEvent") then r:FireServer()
                elseif r:IsA("RemoteFunction") then r:InvokeServer() end
                SafeWait(0.8); return
            end
        end
        for _, obj in pairs(ReplicatedStorage:GetDescendants()) do
            if (obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction")) then
                local n = string.lower(obj.Name)
                if string.find(n, "race") or string.find(n, "v3") or string.find(n, "awaken") then
                    if obj:IsA("RemoteEvent") then obj:FireServer() else obj:InvokeServer() end
                    SafeWait(0.8); return
                end
            end
        end
    end)
end

function V3Activator.Activate()
    local race = RaceDetector.GetCurrentRace()
    Log("INFO", "Kích hoạt V3 (Bấm phím) cho tộc: " .. race)

    local success = false

    -- 1. Mô phỏng bấm phím T (Phím mặc định để bật V3)
    pcall(function()
        local VirtualInputManager = game:GetService("VirtualInputManager")
        -- Bấm xuống
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.T, false, game)
        task.wait(0.1)
        -- Nhả phím
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.T, false, game)
        success = true
    end)

    -- 2. Thử bắn thêm remote (dự phòng)
    FireRaceV3Remote()

    if success then
        Log("OK", "V3 Activator hoàn tất cho " .. race)
        return true
    else
        Log("ERROR", "Không thể mô phỏng bấm phím cho " .. race)
        return false
    end
end


-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI (Responsive PC + Mobile)                           ║
-- ╚══════════════════════════════════════════════════════════╝

local GUI = {}
local guiElements = {}

local COLORS = {
    BG       = Color3.fromRGB(20, 20, 30),
    BORDER   = Color3.fromRGB(80, 80, 120),
    TITLE    = Color3.fromRGB(255, 200, 50),
    TEXT     = Color3.fromRGB(220, 220, 240),
    WAITING  = Color3.fromRGB(255, 200, 50),
    SUCCESS  = Color3.fromRGB(50, 255, 100),
    ERROR    = Color3.fromRGB(255, 70, 70),
    BTN_BG   = Color3.fromRGB(60, 60, 100),
}

local W = IS_MOBILE and 220 or 280
local TS = IS_MOBILE and 11 or 13
local TTS = IS_MOBILE and 13 or 16
local PAD = IS_MOBILE and 7 or 10
local LH = IS_MOBILE and 17 or 22

function GUI.Create()
    pcall(function()
        local old = CoreGui:FindFirstChild("V3SyncGUI")
        if old then old:Destroy() end

        local sg = Instance.new("ScreenGui")
        sg.Name = "V3SyncGUI"
        sg.ResetOnSpawn = false
        sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

        local coreOK = pcall(function() sg.Parent = CoreGui end)
        if not coreOK then
            pcall(function() sg.Parent = LocalPlayer:WaitForChild("PlayerGui") end)
        end

        -- Main Frame
        local mf = Instance.new("Frame")
        mf.Name = "Main"
        mf.Size = UDim2.new(0, W, 0, 180)
        mf.Position = IS_MOBILE and UDim2.new(0, 6, 0, 70) or UDim2.new(0, 12, 0.5, -90)
        mf.BackgroundColor3 = COLORS.BG
        mf.BackgroundTransparency = 0.05
        mf.BorderSizePixel = 0
        mf.Parent = sg
        Instance.new("UICorner", mf).CornerRadius = UDim.new(0, 8)
        local st = Instance.new("UIStroke", mf)
        st.Color = COLORS.BORDER; st.Thickness = 1

        -- Title Bar
        local tb = Instance.new("Frame")
        tb.Size = UDim2.new(1, 0, 0, IS_MOBILE and 26 or 32)
        tb.BackgroundColor3 = Color3.fromRGB(30, 30, 50)
        tb.BackgroundTransparency = 0.2
        tb.BorderSizePixel = 0
        tb.Parent = mf
        Instance.new("UICorner", tb).CornerRadius = UDim.new(0, 8)

        local tl = Instance.new("TextLabel")
        tl.Size = UDim2.new(1, -40, 1, 0)
        tl.Position = UDim2.new(0, PAD, 0, 0)
        tl.BackgroundTransparency = 1
        tl.Text = "⚡ V3 SYNC"
        tl.TextColor3 = COLORS.TITLE
        tl.TextSize = TTS
        tl.Font = Enum.Font.GothamBold
        tl.TextXAlignment = Enum.TextXAlignment.Left
        tl.Parent = tb

        -- Nút thu gọn
        local togBtn = Instance.new("TextButton")
        togBtn.Size = UDim2.new(0, IS_MOBILE and 24 or 30, 0, IS_MOBILE and 18 or 22)
        togBtn.Position = UDim2.new(1, -(IS_MOBILE and 28 or 35), 0.5, -(IS_MOBILE and 9 or 11))
        togBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 80)
        togBtn.Text = "−"
        togBtn.TextColor3 = COLORS.TEXT
        togBtn.TextSize = IS_MOBILE and 12 or 16
        togBtn.Font = Enum.Font.GothamBold
        togBtn.BorderSizePixel = 0
        togBtn.Parent = tb
        Instance.new("UICorner", togBtn).CornerRadius = UDim.new(0, 5)

        -- Content
        local cf = Instance.new("Frame")
        cf.Name = "Content"
        cf.Size = UDim2.new(1, 0, 1, -(IS_MOBILE and 26 or 32))
        cf.Position = UDim2.new(0, 0, 0, IS_MOBILE and 26 or 32)
        cf.BackgroundTransparency = 1
        cf.Parent = mf

        local y = 6

        -- Acc name
        local accLbl = Instance.new("TextLabel")
        accLbl.Size = UDim2.new(1, -PAD*2, 0, LH)
        accLbl.Position = UDim2.new(0, PAD, 0, y)
        accLbl.BackgroundTransparency = 1
        accLbl.Text = "👤 " .. ACC_NAME .. " | " .. (IS_MOBILE and "📱" or "💻")
        accLbl.TextColor3 = COLORS.TEXT
        accLbl.TextSize = TS
        accLbl.Font = Enum.Font.GothamSemibold
        accLbl.TextXAlignment = Enum.TextXAlignment.Left
        accLbl.TextTruncate = Enum.TextTruncate.AtEnd
        accLbl.Parent = cf
        y = y + LH + 1

        -- Tộc
        local raceLbl = Instance.new("TextLabel")
        raceLbl.Size = UDim2.new(1, -PAD*2, 0, LH)
        raceLbl.Position = UDim2.new(0, PAD, 0, y)
        raceLbl.BackgroundTransparency = 1
        raceLbl.Text = "🧬 Detect..."
        raceLbl.TextColor3 = COLORS.TEXT
        raceLbl.TextSize = TS
        raceLbl.Font = Enum.Font.Gotham
        raceLbl.TextXAlignment = Enum.TextXAlignment.Left
        raceLbl.Parent = cf
        guiElements.raceLbl = raceLbl
        y = y + LH + 1

        -- Kết nối
        local connLbl = Instance.new("TextLabel")
        connLbl.Size = UDim2.new(1, -PAD*2, 0, LH)
        connLbl.Position = UDim2.new(0, PAD, 0, y)
        connLbl.BackgroundTransparency = 1
        connLbl.Text = "🌐 Kết nối..."
        connLbl.TextColor3 = COLORS.WAITING
        connLbl.TextSize = TS
        connLbl.Font = Enum.Font.Gotham
        connLbl.TextXAlignment = Enum.TextXAlignment.Left
        connLbl.Parent = cf
        guiElements.connLbl = connLbl
        y = y + LH + 4

        -- Separator
        local sep = Instance.new("Frame")
        sep.Size = UDim2.new(1, -PAD*2, 0, 1)
        sep.Position = UDim2.new(0, PAD, 0, y)
        sep.BackgroundColor3 = COLORS.BORDER
        sep.BackgroundTransparency = 0.5
        sep.BorderSizePixel = 0
        sep.Parent = cf
        y = y + 5

        -- Trạng thái
        local statusLbl = Instance.new("TextLabel")
        statusLbl.Size = UDim2.new(1, -PAD*2, 0, IS_MOBILE and 28 or 35)
        statusLbl.Position = UDim2.new(0, PAD, 0, y)
        statusLbl.BackgroundTransparency = 1
        statusLbl.Text = "⏳ Khởi tạo..."
        statusLbl.TextColor3 = COLORS.WAITING
        statusLbl.TextSize = IS_MOBILE and 12 or 14
        statusLbl.Font = Enum.Font.GothamBold
        statusLbl.TextXAlignment = Enum.TextXAlignment.Left
        statusLbl.TextWrapped = true
        statusLbl.Parent = cf
        guiElements.statusLbl = statusLbl
        y = y + (IS_MOBILE and 32 or 40)

        -- Nút gửi V3 thủ công
        local sendBtn = Instance.new("TextButton")
        sendBtn.Size = UDim2.new(1, -PAD*2, 0, IS_MOBILE and 28 or 32)
        sendBtn.Position = UDim2.new(0, PAD, 0, y)
        sendBtn.BackgroundColor3 = COLORS.BTN_BG
        sendBtn.Text = "🚀 BẬT V3 TẤT CẢ"
        sendBtn.TextColor3 = COLORS.TITLE
        sendBtn.TextSize = IS_MOBILE and 11 or 13
        sendBtn.Font = Enum.Font.GothamBold
        sendBtn.BorderSizePixel = 0
        sendBtn.Parent = cf
        guiElements.sendBtn = sendBtn
        Instance.new("UICorner", sendBtn).CornerRadius = UDim.new(0, 7)
        local bs = Instance.new("UIStroke", sendBtn)
        bs.Color = COLORS.TITLE; bs.Thickness = 1
        y = y + (IS_MOBILE and 32 or 38)

        sendBtn.MouseButton1Click:Connect(function()
            Log("INFO", "Bật V3 cho acc chính và phụ!")
            GUI.UpdateStatus("⚡ Đang bật V3...", COLORS.WAITING)
            
            -- Gửi tín hiệu ngay lập tức trên thread riêng
            task.spawn(function()
                local url = HttpHelper.BuildURL("set", {status = "true", acc = ACC_NAME})
                HttpHelper.Request(url)
            end)
            
            -- Bật V3 cho acc hiện tại
            task.spawn(function()
                local myRace = RaceDetector.GetCurrentRace()
                local activated = V3Activator.Activate()
                if activated then
                    GUI.UpdateStatus("✅ Đã bật V3 & Gửi tín hiệu!", COLORS.SUCCESS)
                else
                    GUI.UpdateStatus("❌ V3 lỗi nhưng đã gửi tín hiệu!", COLORS.ERROR)
                end
            end)
        end)

        -- Resize frame
        local totalH = (IS_MOBILE and 26 or 32) + y + 5
        mf.Size = UDim2.new(0, W, 0, totalH)

        -- Toggle minimize
        local minimized = false
        togBtn.MouseButton1Click:Connect(function()
            minimized = not minimized
            cf.Visible = not minimized
            mf.Size = minimized and UDim2.new(0, W, 0, IS_MOBILE and 26 or 32) or UDim2.new(0, W, 0, totalH)
            togBtn.Text = minimized and "+" or "−"
        end)

        -- Draggable (Touch + Mouse)
        local dragging, dragInput, dragStart, startPos
        tb.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = true; dragStart = input.Position; startPos = mf.Position
                input.Changed:Connect(function()
                    if input.UserInputState == Enum.UserInputState.End then dragging = false end
                end)
            end
        end)
        tb.InputChanged:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
                dragInput = input
            end
        end)
        UserInputService.InputChanged:Connect(function(input)
            if input == dragInput and dragging then
                local d = input.Position - dragStart
                mf.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
            end
        end)

        guiElements.sg = sg; guiElements.mf = mf; guiElements.cf = cf
        Log("OK", "GUI OK (" .. (IS_MOBILE and "Mobile" or "PC") .. ")")
    end)
end

function GUI.UpdateStatus(text, color)
    pcall(function()
        if guiElements.statusLbl then
            guiElements.statusLbl.Text = text
            guiElements.statusLbl.TextColor3 = color or COLORS.TEXT
        end
    end)
end

function GUI.UpdateRace(race)
    pcall(function()
        if guiElements.raceLbl then guiElements.raceLbl.Text = "🧬 " .. tostring(race) end
    end)
end

function GUI.UpdateConnection(ok)
    pcall(function()
        if guiElements.connLbl then
            guiElements.connLbl.Text = ok and "🌐 ✅ Kết nối OK" or "🌐 ❌ Mất kết nối"
            guiElements.connLbl.TextColor3 = ok and COLORS.SUCCESS or COLORS.ERROR
        end
    end)
end


-- ╔══════════════════════════════════════════════════════════╗
-- ║  MAIN LOGIC - AUTO MODE                                 ║
-- ║                                                         ║
-- ║  Mọi acc chạy CÙNG 1 logic:                             ║
-- ║  Thread 1: Theo dõi V3 của mình → gửi tín hiệu nếu bật ║
-- ║  Thread 2: Long Polling API → nhận tín hiệu → bật V3    ║
-- ╚══════════════════════════════════════════════════════════╝

local function Start()
    Log("INFO", "╔══════════════════════════════════════╗")
    Log("INFO", "║  BLOX FRUITS V3 SYNC - AUTO MODE     ║")
    Log("INFO", "║  v2.0 | " .. ACC_NAME)
    Log("INFO", "╚══════════════════════════════════════╝")

    GUI.Create()

    -- Test kết nối API
    local testRes = HttpHelper.Request(HttpHelper.BuildURL("get", {last = "0"}))
    if testRes then
        GUI.UpdateConnection(true)
        if testRes.updated_at then
            g_lastTimestamp = tonumber(testRes.updated_at) or 0
        end
        Log("OK", "API kết nối thành công!")
    else
        GUI.UpdateConnection(false)
        Log("ERROR", "Không kết nối được API!")
    end

    -- Detect tộc
    local race = RaceDetector.GetCurrentRace()
    GUI.UpdateRace(race)

    -- Kiểm tra trạng thái V3 ban đầu
    g_myV3WasOff = not RaceDetector.HasV3()
    Log("INFO", "V3 ban đầu: " .. (g_myV3WasOff and "TẮT" or "BẬT"))

    GUI.UpdateStatus("🔄 Đang chạy...\nBật V3 hoặc chờ tín hiệu", COLORS.WAITING)

    -- ═══════════════════════════════════════════
    --  THREAD 1: Theo dõi V3 của acc mình
    --  Nếu mình bật V3 → gửi tín hiệu cho acc khác
    -- ═══════════════════════════════════════════
    task.spawn(function()
        while g_isRunning do
            pcall(function()
                local currentV3 = RaceDetector.HasV3()

                -- Phát hiện V3 vừa được BẬT (trước đó tắt, giờ bật)
                -- VÀ chưa bị kích hoạt bởi tín hiệu từ acc khác
                if currentV3 and g_myV3WasOff and not g_alreadyActivated then
                    Log("OK", "🎉 V3 của mình vừa BẬT! Gửi tín hiệu cho các acc khác...")
                    GUI.UpdateStatus("📡 Gửi tín hiệu V3...", COLORS.WAITING)

                    local url = HttpHelper.BuildURL("set", {
                        status = "true",
                        acc = ACC_NAME
                    })
                    local res = HttpHelper.Request(url)

                    if res and res.success then
                        GUI.UpdateStatus("✅ Đã gửi! Acc khác sẽ nhận\ntrong < 0.5s", COLORS.SUCCESS)
                        Log("OK", "Gửi tín hiệu V3 thành công!")
                        GUI.UpdateConnection(true)
                    else
                        GUI.UpdateStatus("❌ Gửi thất bại!", COLORS.ERROR)
                        GUI.UpdateConnection(false)
                    end
                end

                -- Cập nhật trạng thái (chỉ khi không phải do tín hiệu từ acc khác)
                if not g_alreadyActivated then
                    g_myV3WasOff = not currentV3
                end
            end)

            SafeWait(1) -- Kiểm tra mỗi 1 giây
        end
    end)

    -- ═══════════════════════════════════════════
    --  THREAD 2: Long Polling chờ tín hiệu từ acc khác
    --  Nếu nhận tín hiệu → tự động bật V3
    -- ═══════════════════════════════════════════
    task.spawn(function()
        while g_isRunning do
            pcall(function()
                local url = HttpHelper.BuildURL("get", {last = tostring(g_lastTimestamp)})
                local res = HttpHelper.Request(url, 1)

                if res then
                    GUI.UpdateConnection(true)

                    if res.updated_at then
                        local newTS = tonumber(res.updated_at) or 0

                        -- Có tín hiệu MỚI + V3 = true + không phải do mình gửi
                        if not res.timeout
                          and res.status == true
                          and newTS > g_lastTimestamp
                          and res.updated_by ~= ACC_NAME then

                            Log("OK", "🎉 NHẬN TÍN HIỆU V3 từ: " .. tostring(res.updated_by))
                            GUI.UpdateStatus("🎉 Nhận tín hiệu từ\n" .. tostring(res.updated_by) .. "!", COLORS.SUCCESS)

                            g_lastTimestamp = newTS
                            g_alreadyActivated = true -- Đánh dấu để Thread 1 không gửi lại

                            -- Detect tộc + kích hoạt V3
                            local myRace = RaceDetector.GetCurrentRace()
                            GUI.UpdateRace(myRace)
                            GUI.UpdateStatus("⚡ Bật " .. myRace .. " V3...", COLORS.WAITING)

                            local activated = V3Activator.Activate()

                            if activated then
                                GUI.UpdateStatus("✅ " .. myRace .. " V3 OK!", COLORS.SUCCESS)
                                HttpHelper.Request(HttpHelper.BuildURL("log", {
                                    acc = ACC_NAME, s = "done",
                                    msg = myRace .. " V3 OK"
                                }))
                                Log("OK", "✅ " .. ACC_NAME .. " bật " .. myRace .. " V3 thành công!")
                            else
                                GUI.UpdateStatus("❌ V3 thất bại!", COLORS.ERROR)
                                HttpHelper.Request(HttpHelper.BuildURL("log", {
                                    acc = ACC_NAME, s = "error",
                                    msg = myRace .. " V3 failed"
                                }))
                            end

                            -- Reset sau 10 giây để sẵn sàng nhận tín hiệu tiếp
                            SafeWait(10)
                            g_alreadyActivated = false
                            g_myV3WasOff = not RaceDetector.HasV3()
                            GUI.UpdateStatus("🔄 Sẵn sàng...\nBật V3 hoặc chờ tín hiệu", COLORS.WAITING)

                        else
                            -- Timeout hoặc tín hiệu từ chính mình → bỏ qua
                            g_lastTimestamp = newTS
                        end
                    end
                else
                    GUI.UpdateConnection(false)
                    GUI.UpdateStatus("❌ Mất kết nối!", COLORS.ERROR)
                    SafeWait(3)
                end
            end)

            task.wait(0.1)
        end
    end)
end

-- Khởi chạy
local ok, err = pcall(Start)
if not ok then
    warn("[V3Sync] Lỗi: " .. tostring(err))
end

LocalPlayer.CharacterRemoving:Connect(function() end)
Log("INFO", "Script loaded! (" .. ACC_NAME .. " | " .. (IS_MOBILE and "Mobile" or "PC") .. ")")
