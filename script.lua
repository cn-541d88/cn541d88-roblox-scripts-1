-- ============================================================
-- 这个脚本的主要用途是用来在那些有管理员的服务器检测管理员是否在服务器内，全部为deepseek大肥鱼编写，目前只测试了xeno注入器在电脑端的效果，忍者啥的没测试
-- 服务器用户名检测工具（精确匹配 + 最小化 + 关闭 + 刷新 + 自动检测）
-- 环境：Roblox 执行器（需支持 writefile/readfile/listfiles/delfile）
-- ============================================================

if not game:IsLoaded() then
    game.Loaded:Wait()
end

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- ============================ 前置声明 ============================
local screenGui
local autoRunning = false
local autoInterval = 5
local autoToggleBtn, autoStatusLabel, autoResultLabel
local showToast                          -- 提前声明，供 startAutoCheck 引用

local COLOR_FOUND = Color3.fromRGB(180, 50, 50)
local COLOR_NOT_FOUND = Color3.fromRGB(0, 140, 80)

-- ============================ 数据状态 ============================
local userList = {}
local currentAutoFile = nil

-- ============================ 文件配置 ============================
local FOLDER_NAME = "UserChecker"
local FOLDER = FOLDER_NAME .. "/"
local AUTO_MARK = FOLDER .. "_autoload.txt"

if not isfolder(FOLDER_NAME) then
    makefolder(FOLDER_NAME)
end

-- ============================ 时间格式化（替代 os.date） ============================
local function getTimeStr()
    local ok, t = pcall(function() return os.time() end)
    if ok and type(t) == "number" then
        local h = math.floor((t / 3600) % 24)
        local m = math.floor((t / 60) % 60)
        local s = math.floor(t % 60)
        return string.format("%02d:%02d:%02d", h, m, s)
    end
    return "--:--:--"
end

-- ============================ 文件工具函数 ============================
local function shortName(path)
    return path:match("([^/\\]+)$") or path
end

local function normalizeFileName(name)
    if not name or name == "" then return nil end
    if not name:match("%.json$") then
        name = name .. ".json"
    end
    return name
end

local function saveToFile(name)
    name = normalizeFileName(name)
    if not name then return false, "文件名不能为空" end
    local ok, err = pcall(function()
        writefile(FOLDER .. name, HttpService:JSONEncode(userList))
    end)
    if ok then return true, "已保存 " .. name else return false, tostring(err) end
end

local function loadFromFile(name)
    name = normalizeFileName(name)
    if not name then return false, "文件名无效" end
    local path = FOLDER .. name
    if not isfile(path) then return false, "文件不存在" end
    local ok, data = pcall(function()
        return HttpService:JSONDecode(readfile(path))
    end)
    if not ok then return false, "读取失败: " .. tostring(data) end
    if type(data) ~= "table" then return false, "文件内容格式错误" end
    userList = data
    return true, "已加载 " .. name
end

local function deleteFile(name)
    name = normalizeFileName(name)
    if not name then return false, "文件名无效" end
    local path = FOLDER .. name
    if not isfile(path) then return false, "文件不存在" end
    local ok, err = pcall(delfile, path)
    if ok then return true, "已删除 " .. name else return false, tostring(err) end
end

local function setAutoLoad(name)
    name = normalizeFileName(name)
    if not name then return false, "文件名无效" end
    if not isfile(FOLDER .. name) then return false, "文件不存在" end
    local ok, err = pcall(writefile, AUTO_MARK, name)
    if ok then
        currentAutoFile = name
        return true, "已将 " .. name .. " 设为自动加载"
    else
        return false, tostring(err)
    end
end

local function getAutoMark()
    if isfile(AUTO_MARK) then
        local ok, content = pcall(readfile, AUTO_MARK)
        if ok and content and content ~= "" then
            return content
        end
    end
    return nil
end

local function listSavedFiles()
    local files = {}
    if not isfolder(FOLDER_NAME) then return files end
    local ok, paths = pcall(listfiles, FOLDER_NAME)
    if not ok or type(paths) ~= "table" then return files end
    for _, p in ipairs(paths) do
        local s = shortName(p)
        if s and s:match("%.json$") then
            table.insert(files, s)
        end
    end
    table.sort(files)
    return files
end

-- ============================ 检测核心逻辑（精确匹配） ============================
local function checkServer()
    if #userList == 0 then
        return "列表为空，请先添加用户名", false
    end
    local players = Players:GetPlayers()
    local found = {}
    for _, target in ipairs(userList) do
        local tLower = string.lower(target)
        for _, p in ipairs(players) do
            if string.lower(p.Name) == tLower then
                if not table.find(found, p.Name) then
                    table.insert(found, p.Name)
                end
                break
            end
        end
    end
    if #found > 0 then
        return "找到: " .. table.concat(found, ", "), true
    else
        return "未找到匹配玩家", false
    end
end

-- ============================ 自动检测引擎 ============================
local function updateAutoUI()
    if autoToggleBtn and autoToggleBtn.Parent then
        if autoRunning then
            autoToggleBtn.Text = "关闭自动检测"
            autoToggleBtn.BackgroundColor3 = Color3.fromRGB(160, 55, 55)
        else
            autoToggleBtn.Text = "开始自动检测"
            autoToggleBtn.BackgroundColor3 = Color3.fromRGB(50, 120, 75)
        end
    end
    if autoStatusLabel and autoStatusLabel.Parent then
        autoStatusLabel.Text = autoRunning and "● 状态: 运行中" or "○ 状态: 已停止"
        autoStatusLabel.TextColor3 = autoRunning and Color3.fromRGB(120, 230, 150) or Color3.fromRGB(180, 180, 200)
    end
end

local function stopAutoCheck()
    if not autoRunning then return end
    autoRunning = false
    updateAutoUI()
end

local function startAutoCheck()
    if #userList == 0 then return false end
    if autoRunning then return true end
    autoRunning = true
    updateAutoUI()

    task.spawn(function()
        while autoRunning and screenGui and screenGui.Parent do
            if #userList == 0 then
                autoRunning = false
                updateAutoUI()
                if autoResultLabel and autoResultLabel.Parent then
                    autoResultLabel.Text = "列表已清空，自动检测已自动停止"
                    autoResultLabel.TextColor3 = Color3.fromRGB(230, 150, 150)
                end
                break
            end

            -- 用 pcall 包裹每一轮检测，单次出错也不会中断整个循环
            local ok, err = pcall(function()
                local msg, matched = checkServer()
                if autoResultLabel and autoResultLabel.Parent then
                    autoResultLabel.Text = "[" .. getTimeStr() .. "] " .. msg
                    autoResultLabel.TextColor3 = matched and COLOR_FOUND or Color3.fromRGB(200, 200, 215)
                end
                if matched then
                    showToast("自动检测 " .. msg, true, COLOR_FOUND)
                end
            end)
            if not ok then
                warn("[UserChecker] 自动检测出错:", err)
            end

            -- 手动累加 elapsed 等待，不依赖 os.clock()
            local elapsed = 0
            while autoRunning and elapsed < autoInterval do
                task.wait(0.2)
                elapsed = elapsed + 0.2
            end
        end
    end)
    return true
end

-- ============================ UI 构建 ============================
screenGui = Instance.new("ScreenGui")
screenGui.Name = "UserCheckerGUI"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = PlayerGui

local main = Instance.new("Frame")
main.Name = "Main"
main.Size = UDim2.new(0, 700, 0, 460)
main.Position = UDim2.new(0.5, -350, 0.5, -230)
main.BackgroundColor3 = Color3.fromRGB(24, 24, 30)
main.BorderSizePixel = 0
main.Active = true
main.Draggable = false
main.Parent = screenGui

local mainCorner = Instance.new("UICorner")
mainCorner.CornerRadius = UDim.new(0, 8)
mainCorner.Parent = main

-- ============================ 标题栏 ============================
local titleBar = Instance.new("Frame")
titleBar.Name = "TitleBar"
titleBar.Size = UDim2.new(1, 0, 0, 36)
titleBar.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
titleBar.BorderSizePixel = 0
titleBar.Active = true
titleBar.ZIndex = 2
titleBar.Parent = main

local titleBarCorner = Instance.new("UICorner")
titleBarCorner.CornerRadius = UDim.new(0, 8)
titleBarCorner.Parent = titleBar

local titleText = Instance.new("TextLabel")
titleText.Name = "TitleText"
titleText.Size = UDim2.new(1, -80, 1, 0)
titleText.Position = UDim2.new(0, 12, 0, 0)
titleText.BackgroundTransparency = 1
titleText.Text = "服务器用户名检测工具"
titleText.TextColor3 = Color3.fromRGB(230, 230, 240)
titleText.Font = Enum.Font.GothamBold
titleText.TextSize = 16
titleText.TextXAlignment = Enum.TextXAlignment.Left
titleText.Active = true
titleText.ZIndex = 3
titleText.Parent = titleBar

local minBtn = Instance.new("TextButton")
minBtn.Name = "MinBtn"
minBtn.Size = UDim2.new(0, 28, 0, 28)
minBtn.Position = UDim2.new(1, -66, 0, 4)
minBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
minBtn.BorderSizePixel = 0
minBtn.Text = "-"
minBtn.TextColor3 = Color3.fromRGB(235, 235, 245)
minBtn.Font = Enum.Font.GothamBold
minBtn.TextSize = 20
minBtn.ZIndex = 10
minBtn.Parent = titleBar

local minCorner = Instance.new("UICorner")
minCorner.CornerRadius = UDim.new(0, 6)
minCorner.Parent = minBtn

local closeBtn = Instance.new("TextButton")
closeBtn.Name = "CloseBtn"
closeBtn.Size = UDim2.new(0, 28, 0, 28)
closeBtn.Position = UDim2.new(1, -34, 0, 4)
closeBtn.BackgroundColor3 = Color3.fromRGB(150, 50, 50)
closeBtn.BorderSizePixel = 0
closeBtn.Text = "×"
closeBtn.TextColor3 = Color3.fromRGB(235, 235, 245)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 20
closeBtn.ZIndex = 10
closeBtn.Parent = titleBar

local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(0, 6)
closeCorner.Parent = closeBtn

-- ============================ 恢复悬浮按钮 ============================
local restoreBtn = Instance.new("TextButton")
restoreBtn.Name = "RestoreBtn"
restoreBtn.Size = UDim2.new(0, 140, 0, 38)
restoreBtn.Position = UDim2.new(0.5, -70, 0.5, -230)
restoreBtn.BackgroundColor3 = Color3.fromRGB(60, 90, 160)
restoreBtn.BorderSizePixel = 0
restoreBtn.Text = "打开检测工具"
restoreBtn.TextColor3 = Color3.new(1, 1, 1)
restoreBtn.Font = Enum.Font.GothamBold
restoreBtn.TextSize = 14
restoreBtn.Active = true
restoreBtn.Draggable = true
restoreBtn.Visible = false
restoreBtn.ZIndex = 10
restoreBtn.Parent = screenGui

local restoreCorner = Instance.new("UICorner")
restoreCorner.CornerRadius = UDim.new(0, 8)
restoreCorner.Parent = restoreBtn

-- ============================ 手动拖动 ============================
local dragging = false
local dragStart, startPos

titleText.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = main.Position
    end
end)

titleText.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - dragStart
        main.Position = UDim2.new(
            startPos.X.Scale,
            startPos.X.Offset + delta.X,
            startPos.Y.Scale,
            startPos.Y.Offset + delta.Y
        )
    end
end)

-- ============================ 最小化 / 恢复 / 关闭 ============================
minBtn.MouseButton1Click:Connect(function()
    restoreBtn.Position = main.Position
    main.Visible = false
    restoreBtn.Visible = true
end)

restoreBtn.MouseButton1Click:Connect(function()
    main.Position = restoreBtn.Position
    restoreBtn.Visible = false
    main.Visible = true
end)

closeBtn.MouseButton1Click:Connect(function()
    stopAutoCheck()
    screenGui:Destroy()
end)

-- ============================ 左侧边栏 ============================
local sidebar = Instance.new("Frame")
sidebar.Size = UDim2.new(0, 150, 1, -36)
sidebar.Position = UDim2.new(0, 0, 0, 36)
sidebar.BackgroundColor3 = Color3.fromRGB(16, 16, 22)
sidebar.BorderSizePixel = 0
sidebar.Parent = main

local sidebarLayout = Instance.new("UIListLayout")
sidebarLayout.Padding = UDim.new(0, 6)
sidebarLayout.Parent = sidebar

local sidebarPad = Instance.new("UIPadding")
sidebarPad.PaddingTop = UDim.new(0, 8)
sidebarPad.PaddingLeft = UDim.new(0, 8)
sidebarPad.PaddingRight = UDim.new(0, 8)
sidebarPad.Parent = sidebar

-- ============================ 右侧内容区 ============================
local content = Instance.new("Frame")
content.Size = UDim2.new(1, -150, 1, -36)
content.Position = UDim2.new(0, 150, 0, 36)
content.BackgroundColor3 = Color3.fromRGB(30, 30, 38)
content.BorderSizePixel = 0
content.Parent = main

-- ---------- 通用控件 ----------
local function makeButton(parent, text, size, pos, color)
    local btn = Instance.new("TextButton")
    btn.Size = size
    btn.Position = pos
    btn.BackgroundColor3 = color or Color3.fromRGB(60, 60, 80)
    btn.BorderSizePixel = 0
    btn.Text = text
    btn.TextColor3 = Color3.fromRGB(235, 235, 245)
    btn.Font = Enum.Font.Gotham
    btn.TextSize = 14
    btn.AutoButtonColor = true
    btn.Parent = parent
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 6)
    c.Parent = btn
    return btn
end

local function makeTextBox(parent, placeholder, size, pos)
    local tb = Instance.new("TextBox")
    tb.Size = size
    tb.Position = pos
    tb.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
    tb.BorderSizePixel = 0
    tb.Text = ""
    tb.PlaceholderText = placeholder
    tb.PlaceholderColor3 = Color3.fromRGB(120, 120, 140)
    tb.TextColor3 = Color3.fromRGB(235, 235, 245)
    tb.Font = Enum.Font.Gotham
    tb.TextSize = 14
    tb.TextXAlignment = Enum.TextXAlignment.Left
    tb.ClearTextOnFocus = false
    tb.Parent = parent
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 6)
    c.Parent = tb
    local pad = Instance.new("UIPadding")
    pad.PaddingLeft = UDim.new(0, 8)
    pad.Parent = tb
    return tb
end

local function makeScrollingList(parent, pos, size)
    local sf = Instance.new("ScrollingFrame")
    sf.Position = pos
    sf.Size = size
    sf.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
    sf.BorderSizePixel = 0
    sf.ScrollBarThickness = 6
    sf.CanvasSize = UDim2.new(0, 0, 0, 0)
    sf.AutomaticCanvasSize = Enum.AutomaticSize.Y
    sf.Parent = parent

    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 6)
    c.Parent = sf

    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 4)
    layout.Parent = sf

    local pad = Instance.new("UIPadding")
    pad.PaddingTop = UDim.new(0, 4)
    pad.PaddingLeft = UDim.new(0, 4)
    pad.PaddingRight = UDim.new(0, 4)
    pad.Parent = sf

    return sf
end

-- ---------- Toast 提示（右下角） ----------
local toast
showToast = function(text, isSuccess, colorOverride)
    if toast then
        pcall(function() toast:Destroy() end)
    end
    toast = Instance.new("Frame")
    toast.Size = UDim2.new(0, 320, 0, 60)
    toast.AnchorPoint = Vector2.new(1, 1)
    toast.Position = UDim2.new(1, -20, 1, -20)
    toast.BackgroundColor3 = colorOverride
        or (isSuccess and Color3.fromRGB(0, 140, 80) or Color3.fromRGB(160, 50, 50))
    toast.BorderSizePixel = 0
    toast.ZIndex = 20
    toast.Parent = screenGui

    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 8)
    c.Parent = toast

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -16, 1, -16)
    lbl.Position = UDim2.new(0, 8, 0, 8)
    lbl.BackgroundTransparency = 1
    lbl.Text = text
    lbl.TextColor3 = Color3.new(1, 1, 1)
    lbl.Font = Enum.Font.GothamBold
    lbl.TextSize = 14
    lbl.TextWrapped = true
    lbl.ZIndex = 21
    lbl.Parent = toast

    local localToast = toast
    task.delay(3, function()
        if localToast and localToast.Parent then
            localToast:Destroy()
        end
    end)
end

-- ============================ 页面切换 ============================
local pages = {}

local function switchPage(pageName)
    for name, frame in pairs(pages) do
        frame.Visible = (name == pageName)
    end
end

-- ============================ “主要”页面 ============================
local mainPage = Instance.new("Frame")
mainPage.Size = UDim2.new(1, 0, 1, 0)
mainPage.BackgroundTransparency = 1
mainPage.Parent = content
pages["主要"] = mainPage

local inputBox = makeTextBox(mainPage, "输入用户名...", UDim2.new(0, 300, 0, 34), UDim2.new(0, 12, 0, 12))
local addBtn = makeButton(mainPage, "添加", UDim2.new(0, 80, 0, 34), UDim2.new(0, 322, 0, 12), Color3.fromRGB(50, 110, 70))

local userListFrame = makeScrollingList(mainPage, UDim2.new(0, 12, 0, 56), UDim2.new(1, -24, 0, 220))

local checkBtn = makeButton(mainPage, "检测当前服务器", UDim2.new(0, 160, 0, 40), UDim2.new(0, 12, 0, 288), Color3.fromRGB(60, 90, 160))

local resultLabel = Instance.new("TextLabel")
resultLabel.Size = UDim2.new(1, -24, 0, 80)
resultLabel.Position = UDim2.new(0, 12, 0, 336)
resultLabel.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
resultLabel.BorderSizePixel = 0
resultLabel.Text = "等待检测..."
resultLabel.TextColor3 = Color3.fromRGB(200, 200, 215)
resultLabel.Font = Enum.Font.Gotham
resultLabel.TextSize = 14
resultLabel.TextWrapped = true
resultLabel.Parent = mainPage

local resultCorner = Instance.new("UICorner")
resultCorner.CornerRadius = UDim.new(0, 6)
resultCorner.Parent = resultLabel

local refreshUserList
refreshUserList = function()
    for _, child in ipairs(userListFrame:GetChildren()) do
        if child:IsA("Frame") or child:IsA("TextLabel") or child:IsA("TextButton") then
            child:Destroy()
        end
    end

    if #userList == 0 and autoRunning then
        stopAutoCheck()
        if autoResultLabel and autoResultLabel.Parent then
            autoResultLabel.Text = "列表已清空，自动检测已自动停止"
            autoResultLabel.TextColor3 = Color3.fromRGB(230, 150, 150)
        end
    end

    if #userList == 0 then
        local empty = Instance.new("TextLabel")
        empty.Size = UDim2.new(1, -8, 0, 30)
        empty.BackgroundTransparency = 1
        empty.Text = "  (列表为空)"
        empty.TextColor3 = Color3.fromRGB(120, 120, 140)
        empty.Font = Enum.Font.Gotham
        empty.TextSize = 13
        empty.TextXAlignment = Enum.TextXAlignment.Left
        empty.Parent = userListFrame
        return
    end

    for i, name in ipairs(userList) do
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, -8, 0, 30)
        row.BackgroundColor3 = Color3.fromRGB(28, 28, 36)
        row.BorderSizePixel = 0
        row.Parent = userListFrame

        local rowCorner = Instance.new("UICorner")
        rowCorner.CornerRadius = UDim.new(0, 4)
        rowCorner.Parent = row

        local nameLabel = Instance.new("TextLabel")
        nameLabel.Size = UDim2.new(1, -70, 1, 0)
        nameLabel.Position = UDim2.new(0, 8, 0, 0)
        nameLabel.BackgroundTransparency = 1
        nameLabel.Text = name
        nameLabel.TextColor3 = Color3.fromRGB(230, 230, 240)
        nameLabel.Font = Enum.Font.Gotham
        nameLabel.TextSize = 13
        nameLabel.TextXAlignment = Enum.TextXAlignment.Left
        nameLabel.Parent = row

        local delBtn = makeButton(row, "删除", UDim2.new(0, 56, 0, 22), UDim2.new(1, -62, 0, 4), Color3.fromRGB(150, 50, 50))
        delBtn.TextSize = 12
        delBtn.MouseButton1Click:Connect(function()
            table.remove(userList, i)
            task.defer(refreshUserList)
        end)
    end
end

addBtn.MouseButton1Click:Connect(function()
    local name = inputBox.Text:gsub("%s+", "")
    if name == "" then
        showToast("请输入用户名", false)
        return
    end
    if table.find(userList, name) then
        showToast("该用户名已存在", false)
        return
    end
    table.insert(userList, name)
    inputBox.Text = ""
    refreshUserList()
    showToast("已添加: " .. name, true)
end)

-- 手动检测：找到=红，未找到=绿
checkBtn.MouseButton1Click:Connect(function()
    local msg, matched = checkServer()
    resultLabel.Text = msg
    resultLabel.TextColor3 = matched and COLOR_FOUND or COLOR_NOT_FOUND
    showToast(msg, matched, matched and COLOR_FOUND or COLOR_NOT_FOUND)
end)

-- ============================ “自动”页面 ============================
local autoPage = Instance.new("Frame")
autoPage.Size = UDim2.new(1, 0, 1, 0)
autoPage.BackgroundTransparency = 1
autoPage.Visible = false
autoPage.Parent = content
pages["自动"] = autoPage

local autoTitle = Instance.new("TextLabel")
autoTitle.Size = UDim2.new(1, -24, 0, 26)
autoTitle.Position = UDim2.new(0, 12, 0, 12)
autoTitle.BackgroundTransparency = 1
autoTitle.Text = "每隔一段时间自动检测当前服务器，找到目标时显示结果"
autoTitle.TextColor3 = Color3.fromRGB(180, 180, 200)
autoTitle.Font = Enum.Font.Gotham
autoTitle.TextSize = 13
autoTitle.TextXAlignment = Enum.TextXAlignment.Left
autoTitle.Parent = autoPage

local intervalLabel = Instance.new("TextLabel")
intervalLabel.Size = UDim2.new(0, 120, 0, 34)
intervalLabel.Position = UDim2.new(0, 12, 0, 48)
intervalLabel.BackgroundTransparency = 1
intervalLabel.Text = "检测间隔（秒）"
intervalLabel.TextColor3 = Color3.fromRGB(230, 230, 240)
intervalLabel.Font = Enum.Font.Gotham
intervalLabel.TextSize = 14
intervalLabel.TextXAlignment = Enum.TextXAlignment.Left
intervalLabel.Parent = autoPage

local intervalBox = makeTextBox(autoPage, "5", UDim2.new(0, 120, 0, 34), UDim2.new(0, 138, 0, 48))
intervalBox.Text = tostring(autoInterval)
intervalBox.TextXAlignment = Enum.TextXAlignment.Center

local toggleHolder = Instance.new("Frame")
toggleHolder.Size = UDim2.new(0, 320, 0, 52)
toggleHolder.Position = UDim2.new(0, 12, 0, 96)
toggleHolder.BackgroundTransparency = 1
toggleHolder.Parent = autoPage

autoToggleBtn = makeButton(toggleHolder, "开始自动检测", UDim2.new(1, 0, 1, 0), UDim2.new(0, 0, 0, 0), Color3.fromRGB(50, 120, 75))
autoToggleBtn.TextSize = 17
autoToggleBtn.Font = Enum.Font.GothamBold

autoStatusLabel = Instance.new("TextLabel")
autoStatusLabel.Size = UDim2.new(1, -24, 0, 26)
autoStatusLabel.Position = UDim2.new(0, 12, 0, 160)
autoStatusLabel.BackgroundTransparency = 1
autoStatusLabel.Text = "○ 状态: 已停止"
autoStatusLabel.TextColor3 = Color3.fromRGB(180, 180, 200)
autoStatusLabel.Font = Enum.Font.GothamBold
autoStatusLabel.TextSize = 14
autoStatusLabel.TextXAlignment = Enum.TextXAlignment.Left
autoStatusLabel.Parent = autoPage

autoResultLabel = Instance.new("TextLabel")
autoResultLabel.Size = UDim2.new(1, -24, 0, 200)
autoResultLabel.Position = UDim2.new(0, 12, 0, 194)
autoResultLabel.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
autoResultLabel.BorderSizePixel = 0
autoResultLabel.Text = "尚未开始自动检测"
autoResultLabel.TextColor3 = Color3.fromRGB(200, 200, 215)
autoResultLabel.Font = Enum.Font.Gotham
autoResultLabel.TextSize = 14
autoResultLabel.TextWrapped = true
autoResultLabel.TextXAlignment = Enum.TextXAlignment.Left
autoResultLabel.TextYAlignment = Enum.TextYAlignment.Top
autoResultLabel.Parent = autoPage

local autoResultCorner = Instance.new("UICorner")
autoResultCorner.CornerRadius = UDim.new(0, 6)
autoResultCorner.Parent = autoResultLabel

local autoResultPad = Instance.new("UIPadding")
autoResultPad.PaddingTop = UDim.new(0, 8)
autoResultPad.PaddingLeft = UDim.new(0, 8)
autoResultPad.PaddingRight = UDim.new(0, 8)
autoResultPad.Parent = autoResultLabel

intervalBox.FocusLost:Connect(function()
    local n = tonumber(intervalBox.Text)
    if n and n >= 1 and n <= 3600 then
        autoInterval = n
        intervalBox.Text = tostring(n)
        showToast("间隔已设为 " .. n .. " 秒", true)
    else
        intervalBox.Text = tostring(autoInterval)
        showToast("请输入 1-3600 之间的整数", false)
    end
end)

autoToggleBtn.MouseButton1Click:Connect(function()
    if autoRunning then
        stopAutoCheck()
        showToast("已关闭自动检测", false)
    else
        if #userList == 0 then
            showToast("列表为空，无法开启自动检测", false)
            return
        end
        local ok = startAutoCheck()
        if ok then
            showToast("已开启自动检测，间隔 " .. autoInterval .. " 秒", true)
        else
            showToast("无法开启自动检测", false)
        end
    end
end)

-- ============================ “文件”页面 ============================
local filePage = Instance.new("Frame")
filePage.Size = UDim2.new(1, 0, 1, 0)
filePage.BackgroundTransparency = 1
filePage.Visible = false
filePage.Parent = content
pages["文件"] = filePage

local fileInput = makeTextBox(filePage, "文件名（不含 .json 也可）", UDim2.new(0, 260, 0, 34), UDim2.new(0, 12, 0, 12))
local saveBtn = makeButton(filePage, "保存当前列表", UDim2.new(0, 110, 0, 34), UDim2.new(0, 280, 0, 12), Color3.fromRGB(50, 110, 70))
local refreshBtn = makeButton(filePage, "刷新", UDim2.new(0, 80, 0, 34), UDim2.new(0, 398, 0, 12), Color3.fromRGB(70, 80, 120))

local autoStatus = Instance.new("TextLabel")
autoStatus.Size = UDim2.new(1, -24, 0, 28)
autoStatus.Position = UDim2.new(0, 12, 0, 54)
autoStatus.BackgroundTransparency = 1
autoStatus.Text = "当前自动加载: (无)"
autoStatus.TextColor3 = Color3.fromRGB(180, 180, 200)
autoStatus.Font = Enum.Font.Gotham
autoStatus.TextSize = 13
autoStatus.TextXAlignment = Enum.TextXAlignment.Left
autoStatus.Parent = filePage

local fileListFrame = makeScrollingList(filePage, UDim2.new(0, 12, 0, 86), UDim2.new(1, -24, 0, 340))

local refreshFileList
refreshFileList = function()
    for _, child in ipairs(fileListFrame:GetChildren()) do
        if child:IsA("Frame") or child:IsA("TextLabel") then
            child:Destroy()
        end
    end

    local files = listSavedFiles()
    local autoMark = getAutoMark()
    currentAutoFile = autoMark

    if autoMark then
        autoStatus.Text = "当前自动加载: " .. autoMark
    else
        autoStatus.Text = "当前自动加载: (无)"
    end

    if #files == 0 then
        local empty = Instance.new("TextLabel")
        empty.Size = UDim2.new(1, -8, 0, 30)
        empty.BackgroundTransparency = 1
        empty.Text = "  (暂无已保存文件)"
        empty.TextColor3 = Color3.fromRGB(120, 120, 140)
        empty.Font = Enum.Font.Gotham
        empty.TextSize = 13
        empty.TextXAlignment = Enum.TextXAlignment.Left
        empty.Parent = fileListFrame
        return
    end

    for _, fileName in ipairs(files) do
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, -8, 0, 32)
        row.BackgroundColor3 = Color3.fromRGB(28, 28, 36)
        row.BorderSizePixel = 0
        row.Parent = fileListFrame

        local rowCorner = Instance.new("UICorner")
        rowCorner.CornerRadius = UDim.new(0, 4)
        rowCorner.Parent = row

        local nameLabel = Instance.new("TextLabel")
        nameLabel.Size = UDim2.new(1, -220, 1, 0)
        nameLabel.Position = UDim2.new(0, 8, 0, 0)
        nameLabel.BackgroundTransparency = 1
        nameLabel.Text = fileName .. (autoMark == fileName and "  [自动]" or "")
        nameLabel.TextColor3 = (autoMark == fileName) and Color3.fromRGB(120, 230, 150) or Color3.fromRGB(230, 230, 240)
        nameLabel.Font = Enum.Font.Gotham
        nameLabel.TextSize = 13
        nameLabel.TextXAlignment = Enum.TextXAlignment.Left
        nameLabel.Parent = row

        local loadBtn = makeButton(row, "加载", UDim2.new(0, 60, 0, 24), UDim2.new(1, -214, 0, 4), Color3.fromRGB(60, 90, 160))
        loadBtn.TextSize = 12
        loadBtn.MouseButton1Click:Connect(function()
            local ok, msg = loadFromFile(fileName)
            if ok then
                refreshUserList()
                showToast(msg, true)
            else
                showToast(msg, false)
                task.defer(refreshFileList)
            end
        end)

        local autoBtn = makeButton(row, "自动", UDim2.new(0, 60, 0, 24), UDim2.new(1, -150, 0, 4), Color3.fromRGB(120, 100, 50))
        autoBtn.TextSize = 12
        autoBtn.MouseButton1Click:Connect(function()
            local ok, msg = setAutoLoad(fileName)
            if ok then
                task.defer(refreshFileList)
                showToast(msg, true)
            else
                showToast(msg, false)
                task.defer(refreshFileList)
            end
        end)

        local delBtn = makeButton(row, "删除", UDim2.new(0, 60, 0, 24), UDim2.new(1, -86, 0, 4), Color3.fromRGB(150, 50, 50))
        delBtn.TextSize = 12
        delBtn.MouseButton1Click:Connect(function()
            local ok, msg = deleteFile(fileName)
            if ok then
                showToast(msg, true)
            else
                showToast(msg, false)
            end
            task.defer(refreshFileList)
        end)
    end
end

saveBtn.MouseButton1Click:Connect(function()
    if #userList == 0 then
        showToast("当前列表为空，无法保存", false)
        return
    end
    local name = fileInput.Text
    if not name or name == "" then
        showToast("请输入文件名", false)
        return
    end
    local ok, msg = saveToFile(name)
    if ok then
        fileInput.Text = ""
        task.defer(refreshFileList)
        showToast(msg, true)
    else
        showToast(msg, false)
    end
end)

refreshBtn.MouseButton1Click:Connect(function()
    task.defer(refreshFileList)
    showToast("已刷新文件列表", true)
end)

-- ============================ 侧边栏按钮 ============================
local sidebarButtons = {}

local function makeSidebarButton(text, pageName)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, 40)
    btn.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
    btn.BorderSizePixel = 0
    btn.Text = text
    btn.TextColor3 = Color3.fromRGB(230, 230, 240)
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 15
    btn.Parent = sidebar
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 6)
    c.Parent = btn
    sidebarButtons[pageName] = btn
    btn.MouseButton1Click:Connect(function()
        switchPage(pageName)
        for name, b in pairs(sidebarButtons) do
            b.BackgroundColor3 = (name == pageName) and Color3.fromRGB(60, 90, 160) or Color3.fromRGB(40, 40, 55)
        end
        if pageName == "文件" then
            task.defer(refreshFileList)
        elseif pageName == "自动" then
            updateAutoUI()
        end
    end)
    return btn
end

makeSidebarButton("主要", "主要")
makeSidebarButton("自动", "自动")
makeSidebarButton("文件", "文件")

-- ============================ 初始化 ============================
switchPage("主要")
for name, b in pairs(sidebarButtons) do
    b.BackgroundColor3 = (name == "主要") and Color3.fromRGB(60, 90, 160) or Color3.fromRGB(40, 40, 55)
end

local autoMark = getAutoMark()
if autoMark and isfile(FOLDER .. autoMark) then
    local ok, msg = loadFromFile(autoMark)
    if ok then
        currentAutoFile = autoMark
        print("[UserChecker] 自动加载成功:", msg)
    else
        print("[UserChecker] 自动加载失败:", msg)
    end
end

refreshUserList()
refreshFileList()
updateAutoUI()

print("[UserChecker] 脚本已加载")
