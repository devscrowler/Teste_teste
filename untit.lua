-- ═══════════════════════════════════════════════════════════════
--  MIRAGE HUB - PROFESSIONAL GUI SYSTEM (COMPLETE) - PATCHED
--  Fixes: robust health reading, safer damage application, debug logs
--  Version: 2.0.3 (patched aura/esp fixes) + GUI parent/position fixes
-- ═══════════════════════════════════════════════════════════════

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

-- Note: LocalPlayer may be nil if this script runs on the server.
local LocalPlayer = Players.LocalPlayer

-- Toggle debug prints
local DEBUG = true

-- CONFIG
local CONFIG = {
    Colors = {
        Background = Color3.fromRGB(18, 18, 22),
        Surface = Color3.fromRGB(25, 25, 30),
        SurfaceLight = Color3.fromRGB(32, 32, 37),
        Primary = Color3.fromRGB(88, 101, 242),
        Accent = Color3.fromRGB(114, 137, 218),
        TextPrimary = Color3.fromRGB(255, 255, 255),
        TextSecondary = Color3.fromRGB(142, 146, 151),
        Border = Color3.fromRGB(40, 40, 45),
        Success = Color3.fromRGB(67, 181, 129),
        Warning = Color3.fromRGB(250, 166, 26),
        Danger = Color3.fromRGB(237, 66, 69),
        MacRed = Color3.fromRGB(255, 95, 86),
        MacYellow = Color3.fromRGB(255, 189, 46),
        MacGreen = Color3.fromRGB(40, 201, 64)
    },
    Sizes = {
        Normal = UDim2.new(0, 320, 0, 260),
        Floating = UDim2.new(0, 180, 0, 34),
        Fullscreen = UDim2.new(1, 0, 1, 0)
    },
    Positions = {
        Normal = UDim2.new(0.5, -160, 0.5, -130),
        Floating = UDim2.new(1, -210, 1, -90),
        Fullscreen = UDim2.new(0, 0, 0, 0)
    },
    Animation = {
        Fast = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        Normal = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        Smooth = TweenInfo.new(0.30, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
    }
}

local function debugPrint(...)
    if DEBUG then
        pcall(function() print("[MirageDebug]", ...) end)
    end
end

-- UTILITIES
local function createInstance(className, properties)
    local instance = Instance.new(className)
    for property, value in pairs(properties) do
        instance[property] = value
    end
    return instance
end

local function applyCorner(parent, radius)
    return createInstance("UICorner", {
        CornerRadius = UDim.new(0, radius),
        Parent = parent
    })
end

local function applyStroke(parent, color, thickness)
    return createInstance("UIStroke", {
        Color = color,
        Thickness = thickness,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Parent = parent
    })
end

local function tween(object, properties, tweenInfo)
    TweenService:Create(object, tweenInfo or CONFIG.Animation.Normal, properties):Play()
end

-- SAFE SCREENGUI CREATION
local ScreenGui = createInstance("ScreenGui", {
    Name = "MirageHubPro",
    ResetOnSpawn = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    IgnoreGuiInset = true
})

-- Robust parenting: prefer PlayerGui on client. Fallback to CoreGui if absolutely needed (and allowed).
local function safeParentScreenGui(sg)
    debugPrint("safeParentScreenGui: RunService:IsClient() =", RunService:IsClient())
    -- If running on the client, parent directly to PlayerGui (most reliable)
    if RunService:IsClient() then
        -- Try the common case first
        local player = Players.LocalPlayer
        if not player then
            debugPrint("safeParentScreenGui: Players.LocalPlayer is nil; waiting for PlayerAdded...")
            -- Wait for a player to be added (this yields until the client player exists)
            player = Players.PlayerAdded:Wait()
        end
        if player and typeof(player) == "Instance" then
            -- store LocalPlayer for other code
            LocalPlayer = player
            -- prefer WaitForChild for PlayerGui but fall back to direct property
            local ok, pg = pcall(function() return player:WaitForChild("PlayerGui", 5) end)
            if ok and pg then
                sg.Parent = pg
                debugPrint("MirageHubPro: parented to PlayerGui (WaitForChild)")
                return
            end
            if player.PlayerGui then
                sg.Parent = player.PlayerGui
                debugPrint("MirageHubPro: parented to PlayerGui (direct)")
                return
            end

            -- As a last resort on client try CoreGui (exploit-like contexts); pcall so we don't error
            local okCore, errCore = pcall(function() sg.Parent = game:GetService("CoreGui") end)
            if okCore and sg.Parent == game:GetService("CoreGui") then
                debugPrint("MirageHubPro: parented to CoreGui")
                return
            end

            -- If everything failed, warn and still leave sg.Parent as-is (developer can inspect)
            warn("MirageHubPro: failed to parent to PlayerGui or CoreGui. GUI may not appear for the player. Parent:", sg.Parent)
        else
            warn("safeParentScreenGui: couldn't resolve player instance on client")
        end
    else
        -- Server environment: parenting a ScreenGui here will not make it show to clients.
        local ok, err = pcall(function() sg.Parent = game:GetService("StarterGui") end)
        if ok then
            debugPrint("MirageHubPro: parented to StarterGui (server). Note: this script appears to be running on server; GUI must be created on client to display.")
        else
            warn("MirageHubPro: running on server and couldn't parent to StarterGui.", err)
        end
    end
end

safeParentScreenGui(ScreenGui)
debugPrint("MirageHubPro: Parent final ->", ScreenGui.Parent)
debugPrint("MirageHubPro: script started", LocalPlayer)

-- NOTIFICATION SYSTEM (defined early so other code can call createNotification safely)
local NotificationContainer = createInstance("Frame", {
    Name = "NotificationContainer",
    Size = UDim2.new(0, 200, 1, -20),
    Position = UDim2.new(1, -210, 0, 12),
    BackgroundTransparency = 1,
    Parent = ScreenGui
})

createInstance("UIListLayout", {
    Padding = UDim.new(0, 6),
    SortOrder = Enum.SortOrder.LayoutOrder,
    VerticalAlignment = Enum.VerticalAlignment.Bottom,
    Parent = NotificationContainer
})

local function createNotification(title, message, duration, notifType)
    local notif = createInstance("Frame", {
        Size = UDim2.new(1, 0, 0, 56),
        BackgroundColor3 = CONFIG.Colors.Surface,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        Parent = NotificationContainer
    })
    
    applyCorner(notif, 8)
    applyStroke(notif, CONFIG.Colors.Border, 1)
    
    createInstance("Frame", {
        Size = UDim2.new(0, 6, 1, 0),
        BackgroundColor3 = notifType == "success" and CONFIG.Colors.Success or 
                           notifType == "warning" and CONFIG.Colors.Warning or
                           notifType == "error" and CONFIG.Colors.Danger or CONFIG.Colors.Primary,
        BorderSizePixel = 0,
        Parent = notif
    })
    
    createInstance("TextLabel", {
        Size = UDim2.new(0, 24, 0, 24),
        Position = UDim2.new(0, 10, 0, 12),
        BackgroundTransparency = 1,
        Text = notifType == "success" and "✓" or notifType == "warning" and "⚠" or notifType == "error" and "✕" or "ℹ",
        TextColor3 = notifType == "success" and CONFIG.Colors.Success or 
                     notifType == "warning" and CONFIG.Colors.Warning or
                     notifType == "error" and CONFIG.Colors.Danger or CONFIG.Colors.Primary,
        Font = Enum.Font.GothamBold,
        TextSize = 18,
        Parent = notif
    })
    
    createInstance("TextLabel", {
        Size = UDim2.new(1, -52, 0, 14),
        Position = UDim2.new(0, 46, 0, 8),
        BackgroundTransparency = 1,
        Text = title,
        TextColor3 = CONFIG.Colors.TextPrimary,
        Font = Enum.Font.GothamBold,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = notif
    })
    
    createInstance("TextLabel", {
        Size = UDim2.new(1, -52, 0, 34),
        Position = UDim2.new(0, 46, 0, 22),
        BackgroundTransparency = 1,
        Text = message,
        TextColor3 = CONFIG.Colors.TextSecondary,
        Font = Enum.Font.Gotham,
        TextSize = 9,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextWrapped = true,
        Parent = notif
    })
    
    notif.Size = UDim2.new(1, 0, 0, 0)
    tween(notif, {Size = UDim2.new(1, 0, 0, 56)}, CONFIG.Animation.Normal)
    
    task.delay(duration or 3, function()
        tween(notif, {Size = UDim2.new(1, 0, 0, 0)}, CONFIG.Animation.Normal)
        task.wait(0.26)
        notif:Destroy()
    end)
end

-- MAIN FRAME
local MainFrame = createInstance("Frame", {
    Name = "MainFrame",
    Size = CONFIG.Sizes.Normal,
    Position = CONFIG.Positions.Normal,
    -- Make AnchorPoint centered so the "Normal" position centers the frame reliably
    AnchorPoint = Vector2.new(0.5, 0.5),
    BackgroundColor3 = CONFIG.Colors.Background,
    BorderSizePixel = 0,
    ClipsDescendants = true,
    Parent = ScreenGui
})

applyCorner(MainFrame, 8)
applyStroke(MainFrame, CONFIG.Colors.Border, 1)

local Shadow = createInstance("ImageLabel", {
    Name = "Shadow",
    BackgroundTransparency = 1,
    Position = UDim2.new(0, -8, 0, -8),
    Size = UDim2.new(1, 16, 1, 16),
    ZIndex = 0,
    Image = "rbxassetid://6014261993",
    ImageColor3 = Color3.fromRGB(0, 0, 0),
    ImageTransparency = 0.55,
    ScaleType = Enum.ScaleType.Slice,
    SliceCenter = Rect.new(100, 100, 100, 100),
    Parent = MainFrame
})

-- Ensure MainFrame can capture input for dragging
MainFrame.Active = true

-- TITLE BAR
local TitleBar = createInstance("Frame", {
    Name = "TitleBar",
    Size = UDim2.new(1, 0, 0, 26),
    BackgroundColor3 = CONFIG.Colors.Surface,
    BorderSizePixel = 0,
    Parent = MainFrame
})

applyCorner(TitleBar, 8)
TitleBar.Active = true -- allow input capture

createInstance("Frame", {
    Size = UDim2.new(1, 0, 0, 5),
    Position = UDim2.new(0, 0, 1, -5),
    BackgroundColor3 = CONFIG.Colors.Surface,
    BorderSizePixel = 0,
    Parent = TitleBar
})

local function createMacCircle(color, position)
    local circle = createInstance("Frame", {
        Size = UDim2.new(0, 6, 0, 6),
        Position = position,
        BackgroundColor3 = color,
        BorderSizePixel = 0,
        Parent = TitleBar
    })
    applyCorner(circle, 4)
    return circle
end

createMacCircle(CONFIG.Colors.MacRed, UDim2.new(0, 8, 0, 10))
createMacCircle(CONFIG.Colors.MacYellow, UDim2.new(0, 20, 0, 10))
createMacCircle(CONFIG.Colors.MacGreen, UDim2.new(0, 32, 0, 10))

local TitleLabel = createInstance("TextLabel", {
    Name = "Title",
    Size = UDim2.new(1, -120, 0, 14),
    Position = UDim2.new(0, 44, 0, 6),
    BackgroundTransparency = 1,
    Text = "Mirage Hub",
    TextColor3 = CONFIG.Colors.TextPrimary,
    Font = Enum.Font.GothamBold,
    TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Left,
    Parent = TitleBar
})

local SubtitleLabel = createInstance("TextLabel", {
    Name = "Subtitle",
    Size = UDim2.new(1, -120, 0, 10),
    Position = UDim2.new(0, 44, 0, 18),
    BackgroundTransparency = 1,
    Text = "Untitled Boxing Game",
    TextColor3 = CONFIG.Colors.TextSecondary,
    Font = Enum.Font.Gotham,
    TextSize = 8,
    TextXAlignment = Enum.TextXAlignment.Left,
    Parent = TitleBar
})

local StatusIndicator = createInstance("Frame", {
    Name = "StatusIndicator",
    Size = UDim2.new(0, 8, 0, 8),
    Position = UDim2.new(1, -84, 0, 9),
    BackgroundColor3 = CONFIG.Colors.Success,
    BorderSizePixel = 0,
    Parent = TitleBar
})

applyCorner(StatusIndicator, 4)

local pulseConnection
pulseConnection = RunService.RenderStepped:Connect(function()
    local time = tick()
    StatusIndicator.BackgroundColor3 = Color3.fromRGB(
        math.floor(67 + math.sin(time * 2) * 12),
        math.floor(181 + math.sin(time * 2) * 12),
        math.floor(129 + math.sin(time * 2) * 12)
    )
end)

local function createControlButton(iconText, name, position, hoverColor)
    local button = createInstance("TextButton", {
        Name = name,
        Size = UDim2.new(0, 18, 0, 18),
        Position = position,
        BackgroundColor3 = CONFIG.Colors.SurfaceLight,
        BorderSizePixel = 0,
        Text = iconText,
        TextColor3 = CONFIG.Colors.TextSecondary,
        Font = Enum.Font.GothamBold,
        TextSize = 12,
        AutoButtonColor = false,
        Parent = TitleBar
    })
    
    applyCorner(button, 6)
    
    button.MouseEnter:Connect(function()
        tween(button, {
            BackgroundColor3 = hoverColor or CONFIG.Colors.Border,
            TextColor3 = CONFIG.Colors.TextPrimary
        }, CONFIG.Animation.Fast)
    end)
    
    button.MouseLeave:Connect(function()
        tween(button, {
            BackgroundColor3 = CONFIG.Colors.SurfaceLight,
            TextColor3 = CONFIG.Colors.TextSecondary
        }, CONFIG.Animation.Fast)
    end)
    
    return button
end

local MinimizeBtn = createControlButton("—", "Minimize", UDim2.new(1, -84, 0, 4), CONFIG.Colors.Border)
local MaximizeBtn = createControlButton("⛶", "Maximize", UDim2.new(1, -56, 0, 4), CONFIG.Colors.Border)
local CloseBtn = createControlButton("✕", "Close", UDim2.new(1, -28, 0, 4), CONFIG.Colors.Danger)

-- CONTENT CONTAINER
local ContentContainer = createInstance("Frame", {
    Name = "Content",
    Size = UDim2.new(1, 0, 1, -56),
    Position = UDim2.new(0, 0, 0, 26),
    BackgroundTransparency = 1,
    Parent = MainFrame
})

-- SIDEBAR
local Sidebar = createInstance("Frame", {
    Name = "Sidebar",
    Size = UDim2.new(0, 90, 1, 0),
    BackgroundColor3 = CONFIG.Colors.Surface,
    BorderSizePixel = 0,
    Parent = ContentContainer
})

local function createSidebarButton(icon, text, position, isActive)
    local button = createInstance("TextButton", {
        Name = text .. "Button",
        Size = UDim2.new(1, -10, 0, 32),
        Position = position,
        BackgroundColor3 = isActive and CONFIG.Colors.SurfaceLight or Color3.fromRGB(0, 0, 0),
        BackgroundTransparency = isActive and 0 or 1,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Text = "",
        Parent = Sidebar
    })
    
    applyCorner(button, 6)
    
    if isActive then
        applyStroke(button, CONFIG.Colors.Primary, 1)
    end
    
    local iconLabel = createInstance("TextLabel", {
        Size = UDim2.new(0, 18, 0, 18),
        Position = UDim2.new(0, 8, 0.5, -9),
        BackgroundTransparency = 1,
        Text = icon,
        TextColor3 = isActive and CONFIG.Colors.Primary or CONFIG.Colors.TextSecondary,
        Font = Enum.Font.GothamBold,
        TextSize = 14,
        Parent = button
    })
    
    local textLabel = createInstance("TextLabel", {
        Size = UDim2.new(1, -36, 1, 0),
        Position = UDim2.new(0, 30, 0, 0),
        BackgroundTransparency = 1,
        Text = text,
        TextColor3 = isActive and CONFIG.Colors.TextPrimary or CONFIG.Colors.TextSecondary,
        Font = isActive and Enum.Font.GothamBold or Enum.Font.Gotham,
        TextSize = 10,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = button
    })
    
    button.MouseEnter:Connect(function()
        if not isActive then
            tween(button, {BackgroundTransparency = 0, BackgroundColor3 = CONFIG.Colors.SurfaceLight}, CONFIG.Animation.Fast)
            tween(textLabel, {TextColor3 = CONFIG.Colors.TextPrimary}, CONFIG.Animation.Fast)
            tween(iconLabel, {TextColor3 = CONFIG.Colors.TextPrimary}, CONFIG.Animation.Fast)
        end
    end)
    
    button.MouseLeave:Connect(function()
        if not isActive then
            tween(button, {BackgroundTransparency = 1}, CONFIG.Animation.Fast)
            tween(textLabel, {TextColor3 = CONFIG.Colors.TextSecondary}, CONFIG.Animation.Fast)
            tween(iconLabel, {TextColor3 = CONFIG.Colors.TextSecondary}, CONFIG.Animation.Fast)
        end
    end)
    
    return button
end

createSidebarButton("⚔️", "Combat", UDim2.new(0, 8, 0, 12), true)
createSidebarButton("👁️", "ESP", UDim2.new(0, 8, 0, 56), false)
createSidebarButton("🎮", "Game", UDim2.new(0, 8, 0, 100), false)
createSidebarButton("⚙️", "Settings", UDim2.new(0, 8, 0, 144), false)

-- MAIN CONTENT
local MainContent = createInstance("Frame", {
    Name = "MainContent",
    Size = UDim2.new(1, -90, 1, 0),
    Position = UDim2.new(0, 90, 0, 0),
    BackgroundTransparency = 1,
    Parent = ContentContainer
})

local ScrollFrame = createInstance("ScrollingFrame", {
    Size = UDim2.new(1, 0, 1, 0),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ScrollBarThickness = 6,
    ScrollBarImageColor3 = CONFIG.Colors.Border,
    CanvasSize = UDim2.new(0, 0, 0, 700),
    Parent = MainContent
})

local PageTitle = createInstance("TextLabel", {
    Size = UDim2.new(1, -20, 0, 20),
    Position = UDim2.new(0, 12, 0, 8),
    BackgroundTransparency = 1,
    Text = "Combat",
    TextColor3 = CONFIG.Colors.TextPrimary,
    Font = Enum.Font.GothamBold,
    TextSize = 14,
    TextXAlignment = Enum.TextXAlignment.Left,
    Parent = ScrollFrame
})

local PageDescription = createInstance("TextLabel", {
    Size = UDim2.new(1, -20, 0, 14),
    Position = UDim2.new(0, 12, 0, 30),
    BackgroundTransparency = 1,
    Text = "Configure combat system settings and automation",
    TextColor3 = CONFIG.Colors.TextSecondary,
    Font = Enum.Font.Gotham,
    TextSize = 9,
    TextXAlignment = Enum.TextXAlignment.Left,
    Parent = ScrollFrame
})

-- SECTION BUILDER
local function createSection(title, description, position, width)
    local section = createInstance("Frame", {
        Name = title,
        Size = UDim2.new(width, -8, 0, 0),
        Position = position,
        BackgroundColor3 = CONFIG.Colors.Surface,
        BorderSizePixel = 0,
        AutomaticSize = Enum.AutomaticSize.Y,
        Parent = ScrollFrame
    })
    
    applyCorner(section, 6)
    applyStroke(section, CONFIG.Colors.Border, 1)
    
    createInstance("UIPadding", {
        PaddingTop = UDim.new(0, 8),
        PaddingBottom = UDim.new(0, 8),
        PaddingLeft = UDim.new(0, 8),
        PaddingRight = UDim.new(0, 8),
        Parent = section
    })
    
    createInstance("TextLabel", {
        Size = UDim2.new(1, 0, 0, 14),
        Position = UDim2.new(0, 0, 0, 0),
        BackgroundTransparency = 1,
        Text = title,
        TextColor3 = CONFIG.Colors.TextPrimary,
        Font = Enum.Font.GothamBold,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = section
    })
    
    if description then
        createInstance("TextLabel", {
            Size = UDim2.new(1, 0, 0, 12),
            Position = UDim2.new(0, 0, 0, 18),
            BackgroundTransparency = 1,
            Text = description,
            TextColor3 = CONFIG.Colors.TextSecondary,
            Font = Enum.Font.Gotham,
            TextSize = 9,
            TextXAlignment = Enum.TextXAlignment.Left,
            Parent = section
        })
    end
    
    local container = createInstance("Frame", {
        Name = "Container",
        Size = UDim2.new(1, 0, 0, 0),
        Position = UDim2.new(0, 0, 0, description and 36 or 28),
        BackgroundTransparency = 1,
        AutomaticSize = Enum.AutomaticSize.Y,
        Parent = section
    })
    
    createInstance("UIListLayout", {
        Padding = UDim.new(0, 8),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = container
    })
    
    return container
end

-- MANTÉM AS SECTIONS MAS REMOVE OS COMPONENTES DA ABA "Combat" (SystemSection)
local SystemSection = createSection("Combat System", "Enable and configure combat automation", UDim2.new(0, 12, 0, 72), 0.48)
local SettingsSection = createSection("Combat Settings", "Fine-tune combat behavior and timing", UDim2.new(0.52, 0, 0, 72), 0.48)

-- === AURAKILL: UI + LOGIC ===
-- State for mob aura
local auraEnabled = false
local auraRange = 200 -- default range (in studs)
local auraDamage = 1000 -- changed to a big but not extreme default (reduce risk of strange in-game clamps)
local auraInterval = 0.18 -- seconds between damage applications per mob
local lastDamageTimes = setmetatable({}, {__mode = "k"}) -- weak keys

-- State for tree aura
local treeAuraEnabled = false
local treeAuraRange = 200 -- default tree range
local treeAuraDamage = 1000
local treeAuraInterval = 0.18
local treeLastDamageTimes = setmetatable({}, {__mode = "k"})

-- Target name tokens (lowercase for matching). We include common variants.
local targetTokens = {
    "wolf",
    "alfa wolf",
    "alpha wolf",
    "bear",
    "bears",
    "cultist",
    "alien",
    "arctic fox",
    "polar bear",
    "mammoth",
    "deer"
}

local treeTokens = {
    "tree",
    "árvore", -- portuguese
    "arvore",
    "trunk",
    "wood",
    "oak",
    "pine"
}

-- Helper: given any descendant (Model or BasePart), try to resolve its top Model
local function resolveModelFromDesc(desc)
    if not desc or typeof(desc) ~= "Instance" then return nil end
    if desc:IsA("Model") then
        return desc
    end
    if desc:IsA("BasePart") then
        local anc = desc:FindFirstAncestorOfClass("Model")
        if anc then return anc end
        if desc.Parent and desc.Parent:IsA("Model") then return desc.Parent end
    end
    if desc.Parent and desc.Parent:IsA("Model") then return desc.Parent end
    return nil
end

-- More tolerant token matching: check model name and a few common descendant names
local function modelNameMatches(model, tokens)
    if not model or typeof(model) ~= "Instance" then return false end
    local name = (model.Name or ""):lower()
    for _, token in ipairs(tokens) do
        if string.find(name, token, 1, true) then
            return true
        end
    end
    for _, child in ipairs(model:GetChildren()) do
        if child:IsA("BasePart") or child:IsA("Folder") or child:IsA("Model") or child:IsA("Instance") then
            local cname = (child.Name or ""):lower()
            for _, token in ipairs(tokens) do
                if string.find(cname, token, 1, true) then
                    return true
                end
            end
        end
    end
    return false
end

-- Helper to get Humanoid and a position-providing BasePart inside the model
local function getModelHumanoidRoot(model)
    if not model or typeof(model) ~= "Instance" then return nil end
    local humanoid
    local direct = model:FindFirstChildOfClass("Humanoid")
    if direct then humanoid = direct end
    if not humanoid then
        for _, d in ipairs(model:GetDescendants()) do
            if d:IsA("Humanoid") then
                humanoid = d
                break
            end
        end
    end

    local root
    local hrp = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("RootPart")
    if hrp and hrp:IsA("BasePart") then root = hrp end
    if not root and model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then
        root = model.PrimaryPart
    end
    if not root then
        for _, d in ipairs(model:GetDescendants()) do
            if d:IsA("BasePart") then
                root = d
                break
            end
        end
    end

    if humanoid and root and root:IsA("BasePart") then
        return humanoid, root
    elseif humanoid then
        return humanoid, root
    end
    return nil
end

-- Robust health reader: tries multiple strategies to get a numeric health
local function readHealth(model)
    if not model or typeof(model) ~= "Instance" then return nil end
    local humanoid, root = getModelHumanoidRoot(model)
    if humanoid then
        if typeof(humanoid.Health) == "number" then
            return humanoid.Health
        end
        -- some games place a child NumberValue called Health under humanoid
        local hv = humanoid:FindFirstChild("Health")
        if hv and typeof(hv.Value) == "number" then
            return hv.Value
        end
    end
    -- fallback: check model's Health NumberValue
    local mHv = model:FindFirstChild("Health")
    if mHv and typeof(mHv.Value) == "number" then
        return mHv.Value
    end
    return nil
end

-- Robust damage applier with safe fallbacks and debug logs
local function applyDamageToModel(model, damage)
    if not model or typeof(model) ~= "Instance" then return false, "no model" end
    local humanoid, root = getModelHumanoidRoot(model)
    local now = tick()

    if humanoid then
        -- prefer TakeDamage if present
        local ok, err = pcall(function()
            if typeof(humanoid.TakeDamage) == "function" then
                humanoid:TakeDamage(damage)
                debugPrint("MirageAura: TakeDamage used on", model:GetFullName(), "dmg=", damage)
                return true
            end
        end)
        if ok then
            -- if pcall succeeded we consider damage applied (even if TakeDamage absent, next steps)
        end

        -- try to set Health property if numeric
        local successSet = false
        pcall(function()
            if typeof(humanoid.Health) == "number" then
                humanoid.Health = math.max(0, (humanoid.Health or 0) - damage)
                successSet = true
                debugPrint("MirageAura: Subtracted from humanoid.Health on", model:GetFullName(), "newHP=", humanoid.Health)
            end
        end)
        if successSet then return true, "health property set" end

        -- try humanoid.Health NumberValue inside humanoid
        local hv = humanoid:FindFirstChild("Health")
        if hv and typeof(hv.Value) == "number" then
            pcall(function()
                hv.Value = math.max(0, hv.Value - damage)
            end)
            debugPrint("MirageAura: Subtracted from humanoid.Health NumberValue on", model:GetFullName(), "newHP=", hv.Value)
            return true, "healthvalue set"
        end

        -- as last resort for humanoid model, try to break joints on root part
        if root and root:IsA("BasePart") then
            pcall(function()
                root:BreakJoints()
            end)
            debugPrint("MirageAura: Broke joints on root (humanoid fallback) for", model:GetFullName())
            return true, "broke joints"
        end

        return false, "humanoid present but no editable health"
    else
        -- no humanoid: try model Health NumberValue
        local mHv = model:FindFirstChild("Health")
        if mHv and typeof(mHv.Value) == "number" then
            pcall(function()
                mHv.Value = math.max(0, mHv.Value - damage)
            end)
            debugPrint("MirageAura: Subtracted from model Health NumberValue on", model:GetFullName(), "newHP=", mHv.Value)
            return true, "model healthvalue"
        end

        -- try breaking main part
        local part = model.PrimaryPart
        if not part then
            for _, c in ipairs(model:GetDescendants()) do
                if c:IsA("BasePart") then
                    part = c
                    break
                end
            end
        end
        if part then
            pcall(function() part:BreakJoints() end)
            debugPrint("MirageAura: Broke joints on part (no humanoid) for", model:GetFullName())
            return true, "broke joints no humanoid"
        end

        return false, "no humanoid and no parts/healthvalue"
    end
end

-- Aura logic: iterate workspace descendants (not only children) and apply damage to unique models
local function runAuraOnce()
    local char = LocalPlayer and LocalPlayer.Character
    local originRoot
    if char then
        originRoot = char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart
    else
        return
    end
    if not originRoot then return end

    local originPos = originRoot.Position
    local processed = {}

    for _, desc in ipairs(workspace:GetDescendants()) do
        local model = resolveModelFromDesc(desc)
        if model and not processed[model] then
            processed[model] = true
            if modelNameMatches(model, targetTokens) then
                local humanoid, hrp = getModelHumanoidRoot(model)
                -- read health robustly
                local hp = readHealth(model)
                if hp and hp > 0 then
                    local pos = hrp and hrp.Position or (model.GetModelCFrame and model:GetModelCFrame().p or nil)
                    if pos then
                        local dist = (pos - originPos).Magnitude
                        if dist <= auraRange then
                            local now = tick()
                            local last = lastDamageTimes[model] or 0
                            if now - last >= auraInterval then
                                local ok, reason = pcall(function()
                                    return applyDamageToModel(model, auraDamage)
                                end)
                                if not ok then
                                    debugPrint("MirageAura: pcall error applying damage to", model:GetFullName(), reason)
                                else
                                    debugPrint("MirageAura: damage attempt on", model:GetFullName(), "result:", reason)
                                end
                                lastDamageTimes[model] = now
                            end
                        end
                    end
                else
                    -- either no health read or dead; skip
                end
            end
        end
    end
end

-- Tree aura logic: target models that look like trees (robust detection + damage attempt)
local function runTreeAuraOnce()
    local char = LocalPlayer and LocalPlayer.Character
    local originRoot
    if char then
        originRoot = char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart
    else
        return
    end
    if not originRoot then return end

    local originPos = originRoot.Position
    local processed = {}

    for _, desc in ipairs(workspace:GetDescendants()) do
        local model = resolveModelFromDesc(desc)
        if model and not processed[model] then
            processed[model] = true
            if modelNameMatches(model, treeTokens) then
                local humanoid, hrp = getModelHumanoidRoot(model)
                local hp = readHealth(model)
                if (hp and hp > 0) and hrp then
                    local dist = (hrp.Position - originPos).Magnitude
                    if dist <= treeAuraRange then
                        local now = tick()
                        local last = treeLastDamageTimes[model] or 0
                        if now - last >= treeAuraInterval then
                            local ok, reason = pcall(function()
                                return applyDamageToModel(model, treeAuraDamage)
                            end)
                            if not ok then
                                debugPrint("MirageTree: pcall error applying damage to", model:GetFullName(), reason)
                            else
                                debugPrint("MirageTree: damage attempt on", model:GetFullName(), "result:", reason)
                            end
                            treeLastDamageTimes[model] = now
                        end
                    end
                else
                    -- no humanoid / no hp: fallback to parts-based check
                    local part
                    if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then
                        part = model.PrimaryPart
                    else
                        for _, c in ipairs(model:GetDescendants()) do
                            if c:IsA("BasePart") then
                                part = c
                                break
                            end
                        end
                    end
                    if part then
                        local dist = (part.Position - originPos).Magnitude
                        if dist <= treeAuraRange then
                            local now = tick()
                            local last = treeLastDamageTimes[model] or 0
                            if now - last >= treeAuraInterval then
                                local ok, reason = pcall(function()
                                    return applyDamageToModel(model, treeAuraDamage)
                                end)
                                if not ok then
                                    debugPrint("MirageTree: pcall error applying damage to (parts)", model:GetFullName(), reason)
                                else
                                    debugPrint("MirageTree: damage attempt on (parts)", model:GetFullName(), "result:", reason)
                                end
                                treeLastDamageTimes[model] = now
                            end
                        end
                    end
                end
            end
        end
    end
end

-- RunService loop to process aura while enabled
local auraConnection
auraConnection = RunService.Heartbeat:Connect(function(dt)
    if auraEnabled then
        pcall(runAuraOnce)
    end
    if treeAuraEnabled then
        pcall(runTreeAuraOnce)
    end
end)

-- UI: create a simple toggle + slider in SystemSection
local function createToggle(text, parent, initial)
    local frame = createInstance("Frame", {
        Size = UDim2.new(1, 0, 0, 32),
        BackgroundTransparency = 1,
        Parent = parent
    })
    local label = createInstance("TextLabel", {
        Size = UDim2.new(0.6, 0, 1, 0),
        BackgroundTransparency = 1,
        Text = text,
        TextColor3 = CONFIG.Colors.TextPrimary,
        Font = Enum.Font.Gotham,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = frame
    })
    local btn = createInstance("TextButton", {
        Size = UDim2.new(0, 56, 0, 18),
        Position = UDim2.new(1, -60, 0.5, -9),
        BackgroundColor3 = initial and CONFIG.Colors.Primary or CONFIG.Colors.SurfaceLight,
        BorderSizePixel = 0,
        Text = initial and "ON" or "OFF",
        TextColor3 = initial and CONFIG.Colors.TextPrimary or CONFIG.Colors.TextSecondary,
        Font = Enum.Font.GothamBold,
        TextSize = 11,
        AutoButtonColor = false,
        Parent = frame
    })
    applyCorner(btn, 6)
    applyStroke(btn, CONFIG.Colors.Border, 1)
    return frame, btn
end

-- Improved slider (0..2000) with robust dragging: handle and bar both start drag; support callback onChange
local function createSlider(labelText, min, max, step, parent, initialValue, onChange)
    local frame = createInstance("Frame", {
        Size = UDim2.new(1, 0, 0, 48),
        BackgroundTransparency = 1,
        Parent = parent
    })
    createInstance("TextLabel", {
        Size = UDim2.new(0.6, 0, 0, 18),
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 0, 0, 0),
        Text = labelText,
        TextColor3 = CONFIG.Colors.TextPrimary,
        Font = Enum.Font.Gotham,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = frame
    })
    local valueLabel = createInstance("TextLabel", {
        Size = UDim2.new(0.35, 0, 0, 18),
        BackgroundTransparency = 1,
        Position = UDim2.new(0.65, 0, 0, 0),
        Text = tostring(initialValue),
        TextColor3 = CONFIG.Colors.TextSecondary,
        Font = Enum.Font.Gotham,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Right,
        Parent = frame
    })
    local bar = createInstance("Frame", {
        Size = UDim2.new(1, 0, 0, 10),
        Position = UDim2.new(0, 0, 0, 24),
        BackgroundColor3 = CONFIG.Colors.SurfaceLight,
        BorderSizePixel = 0,
        Parent = frame
    })
    applyCorner(bar, 6)
    applyStroke(bar, CONFIG.Colors.Border, 1)
    local fill = createInstance("Frame", {
        Size = UDim2.new((initialValue - min) / (max - min), 0, 1, 0),
        BackgroundColor3 = CONFIG.Colors.Primary,
        BorderSizePixel = 0,
        Parent = bar
    })
    applyCorner(fill, 6)
    local handle = createInstance("Frame", {
        Size = UDim2.new(0, 12, 0, 12),
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(fill.Size.X.Scale, 0, 0.5, 0),
        BackgroundColor3 = CONFIG.Colors.Surface,
        BorderSizePixel = 0,
        Parent = bar
    })
    applyCorner(handle, 8)
    applyStroke(handle, CONFIG.Colors.Border, 1)

    local dragging = false

    local function getMouseXFromInput(input)
        if input and input.Position and typeof(input.Position) == "Vector2" then
            return input.Position.X
        end
        local pos = UserInputService:GetMouseLocation()
        if pos and typeof(pos) == "Vector2" then
            return pos.X
        end
        return bar.AbsolutePosition.X
    end

    local function setValueFromX(x)
        local absPos = bar.AbsolutePosition
        local width = bar.AbsoluteSize.X
        if width <= 0 then
            width = math.max(1, (max - min))
            absPos = Vector2.new(bar.AbsolutePosition.X, bar.AbsolutePosition.Y)
        end
        local relative = math.clamp((x - absPos.X) / math.max(1, width), 0, 1)
        local raw = min + relative * (max - min)
        if step and step > 0 then
            raw = math.floor(raw / step + 0.5) * step
        end
        local value = math.clamp(raw, min, max)
        if onChange and typeof(onChange) == "function" then
            pcall(function() onChange(value) end)
        end
        valueLabel.Text = tostring(math.floor(value))
        fill.Size = UDim2.new((value - min) / (max - min), 0, 1, 0)
        handle.Position = UDim2.new(fill.Size.X.Scale, 0, 0.5, 0)
    end

    local function startDrag(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            local x = getMouseXFromInput(input)
            setValueFromX(x)
        end
    end

    bar.InputBegan:Connect(function(input)
        startDrag(input)
    end)
    handle.InputBegan:Connect(function(input)
        startDrag(input)
    end)

    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local x = getMouseXFromInput(input)
            setValueFromX(x)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
            dragging = false
        end
    end)

    return frame, valueLabel
end

-- Create UI elements in SystemSection
local toggleFrame, toggleBtn = createToggle("Aura Kill (Range-based)", SystemSection, false)
local sliderFrame, sliderValueLabel = createSlider("Aura Range (studs)", 0, 2000, 1, SystemSection, auraRange, function(v)
    auraRange = v
end)

-- Tree aura UI: toggle + slider
local treeToggleFrame, treeToggleBtn = createToggle("Tree Aura (Range-based)", SystemSection, false)
local treeSliderFrame, treeSliderValueLabel = createSlider("Tree Aura Range (studs)", 0, 2000, 1, SystemSection, treeAuraRange, function(v)
    treeAuraRange = v
end)

-- Toggle behavior for mob aura
toggleBtn.MouseButton1Click:Connect(function()
    auraEnabled = not auraEnabled
    if auraEnabled then
        toggleBtn.BackgroundColor3 = CONFIG.Colors.Primary
        toggleBtn.Text = "ON"
        toggleBtn.TextColor3 = CONFIG.Colors.TextPrimary
        createNotification("Aura Kill", "Aura Kill ATIVADO. Range: " .. tostring(auraRange) .. " studs", 3, "success")
        debugPrint("MirageAura: ativado, damage:", auraDamage, "range:", auraRange)
    else
        toggleBtn.BackgroundColor3 = CONFIG.Colors.SurfaceLight
        toggleBtn.Text = "OFF"
        toggleBtn.TextColor3 = CONFIG.Colors.TextSecondary
        createNotification("Aura Kill", "Aura Kill DESATIVADO", 2.3, "warning")
        debugPrint("MirageAura: desativado")
    end
end)

-- Toggle behavior for tree aura
treeToggleBtn.MouseButton1Click:Connect(function()
    treeAuraEnabled = not treeAuraEnabled
    if treeAuraEnabled then
        treeToggleBtn.BackgroundColor3 = CONFIG.Colors.Primary
        treeToggleBtn.Text = "ON"
        treeToggleBtn.TextColor3 = CONFIG.Colors.TextPrimary
        createNotification("Tree Aura", "Tree Aura ATIVADO. Range: " .. tostring(treeAuraRange) .. " studs", 3, "success")
        debugPrint("MirageTree: ativado, damage:", treeAuraDamage, "range:", treeAuraRange)
    else
        treeToggleBtn.BackgroundColor3 = CONFIG.Colors.SurfaceLight
        treeToggleBtn.Text = "OFF"
        treeToggleBtn.TextColor3 = CONFIG.Colors.TextSecondary
        createNotification("Tree Aura", "Tree Aura DESATIVADO", 2.3, "warning")
        debugPrint("MirageTree: desativado")
    end
end)

-- Update displayed value labels on initialization
sliderValueLabel.Text = tostring(auraRange)
treeSliderValueLabel.Text = tostring(treeAuraRange)

-- === HEALTH ESP SYSTEM ===
local espEnabled = false
local espBillboards = setmetatable({}, {__mode = "k"}) -- weak keys for garbage
local espConnection

local function createHealthBillboard(model)
    if not model or typeof(model) ~= "Instance" or not model:IsA("Model") then return end
    if model:FindFirstChild("MirageHealthESP") then return end
    local humanoid, hrp = getModelHumanoidRoot(model)
    local part = hrp or model.PrimaryPart
    if not part then
        for _, c in ipairs(model:GetDescendants()) do
            if c:IsA("BasePart") then
                part = c
                break
            end
        end
    end
    if not part then return end

    local bb = Instance.new("BillboardGui")
    bb.Name = "MirageHealthESP"
    bb.Adornee = part
    bb.Size = UDim2.new(0, 120, 0, 24)
    bb.StudsOffsetWorldSpace = Vector3.new(0, 2.2, 0)
    bb.AlwaysOnTop = true
    bb.Parent = model

    local label = Instance.new("TextLabel")
    label.Name = "HealthLabel"
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.Text = "HP: ?"
    label.TextColor3 = CONFIG.Colors.TextPrimary
    label.Font = Enum.Font.GothamBold
    label.TextSize = 12
    label.TextStrokeTransparency = 0.8
    label.Parent = bb

    espBillboards[model] = bb
end

local function removeHealthBillboard(model)
    local bb = espBillboards[model]
    if bb and bb.Parent then
        pcall(function() bb:Destroy() end)
    end
    espBillboards[model] = nil
end

local function updateHealthESPs()
    if not espEnabled then
        for m, b in pairs(espBillboards) do
            if b and b.Parent then pcall(function() b:Destroy() end) end
            espBillboards[m] = nil
        end
        return
    end

    local char = LocalPlayer and LocalPlayer.Character
    if not char then return end

    local processed = {}
    for _, desc in ipairs(workspace:GetDescendants()) do
        local model = resolveModelFromDesc(desc)
        if model and not processed[model] then
            processed[model] = true
            if modelNameMatches(model, targetTokens) then
                local humanoid, hrp = getModelHumanoidRoot(model)
                local hp = readHealth(model)
                if hp ~= nil then
                    if not espBillboards[model] then
                        pcall(function() createHealthBillboard(model) end)
                    end
                    local bb = espBillboards[model]
                    if bb and bb:FindFirstChild("HealthLabel") then
                        bb.HealthLabel.Text = "HP: " .. tostring(math.floor(hp))
                    end
                else
                    if espBillboards[model] then
                        removeHealthBillboard(model)
                    end
                end
            end
        end
    end

    for m, b in pairs(espBillboards) do
        if not m or not m.Parent or not modelNameMatches(m, targetTokens) then
            if b and b.Parent then pcall(function() b:Destroy() end) end
            espBillboards[m] = nil
        end
    end
end

-- Health ESP toggle in UI
local healthToggleFrame, healthToggleBtn = createToggle("Show Mob Health", SystemSection, false)
healthToggleBtn.MouseButton1Click:Connect(function()
    espEnabled = not espEnabled
    if espEnabled then
        healthToggleBtn.BackgroundColor3 = CONFIG.Colors.Primary
        healthToggleBtn.Text = "ON"
        healthToggleBtn.TextColor3 = CONFIG.Colors.TextPrimary
        createNotification("Health ESP", "Mostrando vida dos mobs", 3, "success")
        debugPrint("MirageESP: ativado")
        if not espConnection then
            espConnection = RunService.Heartbeat:Connect(function()
                pcall(updateHealthESPs)
            end)
        end
    else
        healthToggleBtn.BackgroundColor3 = CONFIG.Colors.SurfaceLight
        healthToggleBtn.Text = "OFF"
        healthToggleBtn.TextColor3 = CONFIG.Colors.TextSecondary
        createNotification("Health ESP", "Ocultando vida dos mobs", 2.3, "warning")
        debugPrint("MirageESP: desativado")
        for m, b in pairs(espBillboards) do
            if b and b.Parent then pcall(function() b:Destroy() end) end
            espBillboards[m] = nil
        end
        if espConnection then
            pcall(function() espConnection:Disconnect() end)
            espConnection = nil
        end
    end
end)

-- FOOTER
local Footer = createInstance("Frame", {
    Name = "Footer",
    Size = UDim2.new(1, 0, 0, 20),
    Position = UDim2.new(0, 0, 1, -20),
    BackgroundColor3 = CONFIG.Colors.Surface,
    BorderSizePixel = 0,
    Parent = MainFrame
})

createInstance("Frame", {
    Size = UDim2.new(1, 0, 0, 1),
    BackgroundColor3 = CONFIG.Colors.Border,
    BorderSizePixel = 0,
    Parent = Footer
})

createInstance("TextLabel", {
    Size = UDim2.new(0, 140, 1, 0),
    Position = UDim2.new(0, 8, 0, 0),
    BackgroundTransparency = 1,
    Text = "v2.0.3 • Professional Edition",
    TextColor3 = CONFIG.Colors.TextSecondary,
    Font = Enum.Font.Gotham,
    TextSize = 8,
    TextXAlignment = Enum.TextXAlignment.Left,
    Parent = Footer
})

createInstance("TextLabel", {
    Size = UDim2.new(0, 140, 1, 0),
    Position = UDim2.new(1, -148, 0, 0),
    BackgroundTransparency = 1,
    Text = "● Connected",
    TextColor3 = CONFIG.Colors.Success,
    Font = Enum.Font.GothamMedium,
    TextSize = 8,
    TextXAlignment = Enum.TextXAlignment.Right,
    Parent = Footer
})

-- WINDOW CONTROLS
local currentState = "Normal"
local previousState = "Normal"
local function applyState(state)
    if state == "Floating" then
        tween(MainFrame, {Size = CONFIG.Sizes.Floating, Position = CONFIG.Positions.Floating}, CONFIG.Animation.Fast)
        ContentContainer.Visible = false
        Footer.Visible = false
        MainFrame.Visible = true
    elseif state == "Fullscreen" then
        tween(MainFrame, {Size = CONFIG.Sizes.Fullscreen, Position = CONFIG.Positions.Fullscreen}, CONFIG.Animation.Smooth)
        ContentContainer.Visible = true
        Footer.Visible = true
        MainFrame.Visible = true
    elseif state == "Normal" then
        tween(MainFrame, {Size = CONFIG.Sizes.Normal, Position = CONFIG.Positions.Normal}, CONFIG.Animation.Normal)
        ContentContainer.Visible = true
        Footer.Visible = true
        MainFrame.Visible = true
    end
    currentState = state
end

CloseBtn.MouseButton1Click:Connect(function()
    tween(MainFrame, {
        Size = UDim2.new(0, 0, 0, 0),
        Position = UDim2.new(0.5, 0, 0.5, 0)
    }, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.In))
    task.wait(0.22)
    ScreenGui:Destroy()
end)

MinimizeBtn.MouseButton1Click:Connect(function()
    if currentState ~= "Floating" then
        previousState = currentState
        applyState("Floating")
    else
        applyState(previousState == "Floating" and "Normal" or previousState or "Normal")
    end
end)

MaximizeBtn.MouseButton1Click:Connect(function()
    if currentState ~= "Fullscreen" then
        previousState = currentState
        applyState("Fullscreen")
    else
        applyState("Normal")
    end
end)

-- DRAG SYSTEM
local dragStartPos, dragStartFramePos
local isDragging = false

local function getInputPosition(input)
    if input and input.Position then
        return input.Position
    end
    return UserInputService:GetMouseLocation()
end

local function beginDrag(input)
    if not input then return end
    if not (currentState == "Normal" or currentState == "Floating") then return end

    isDragging = true
    dragStartPos = getInputPosition(input)
    dragStartFramePos = Vector2.new(MainFrame.AbsolutePosition.X, MainFrame.AbsolutePosition.Y)
end

local function updateDrag(input)
    if not isDragging then return end
    local currentPos = getInputPosition(input)
    if not currentPos or not dragStartPos or not dragStartFramePos then return end

    local delta = currentPos - dragStartPos
    local target = dragStartFramePos + delta

    local parentSize = MainFrame.Parent and MainFrame.Parent.AbsoluteSize or Vector2.new(1920, 1080)
    local frameSize = MainFrame.AbsoluteSize

    local clampedX = math.clamp(target.X, 0, math.max(0, parentSize.X - frameSize.X))
    local clampedY = math.clamp(target.Y, 0, math.max(0, parentSize.Y - frameSize.Y))

    -- Convert absolute position to UDim2 anchored at top-left (AnchorPoint is 0.5,0.5; we offset accordingly)
    MainFrame.Position = UDim2.new(0, clampedX + frameSize.X * 0.5, 0, clampedY + frameSize.Y * 0.5)
end

local function endDrag()
    isDragging = false
end

TitleBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        beginDrag(input)
    end
end)

MainFrame.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        beginDrag(input)
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
        updateDrag(input)
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        endDrag()
    end
end)

-- KEYBIND (RightShift toggles visibility)
local isGuiVisible = true
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Enum.KeyCode.RightShift then
        isGuiVisible = not isGuiVisible
        if isGuiVisible then
            MainFrame.Visible = true
            local targetPos = currentState == "Normal" and CONFIG.Positions.Normal or
                              currentState == "Floating" and CONFIG.Positions.Floating or
                              CONFIG.Positions.Fullscreen
            tween(MainFrame, {Position = targetPos}, CONFIG.Animation.Normal)
            createNotification("GUI Shown", "Press Right Shift to hide", 2, "info")
        else
            tween(MainFrame, {Position = UDim2.new(0.5, 0, -0.5, 0)}, CONFIG.Animation.Normal)
            task.wait(0.22)
            MainFrame.Visible = false
        end
    end
end)

-- PERFORMANCE MONITOR (optional)
local PerformanceFrame = createInstance("Frame", {
    Name = "Performance",
    Size = UDim2.new(0, 72, 0, 32),
    Position = UDim2.new(0, 6, 1, -54),
    BackgroundColor3 = CONFIG.Colors.Surface,
    BackgroundTransparency = 0.35,
    BorderSizePixel = 0,
    Visible = false,
    Parent = Sidebar
})

applyCorner(PerformanceFrame, 6)

local FPSLabel = createInstance("TextLabel", {
    Size = UDim2.new(1, -8, 0, 14),
    Position = UDim2.new(0, 4, 0, 4),
    BackgroundTransparency = 1,
    Text = "FPS: 60",
    TextColor3 = CONFIG.Colors.TextPrimary,
    Font = Enum.Font.GothamMedium,
    TextSize = 9,
    TextXAlignment = Enum.TextXAlignment.Left,
    Parent = PerformanceFrame
})

local PingLabel = createInstance("TextLabel", {
    Size = UDim2.new(1, -8, 0, 14),
    Position = UDim2.new(0, 4, 0, 18),
    BackgroundTransparency = 1,
    Text = "Ping: 0ms",
    TextColor3 = CONFIG.Colors.TextPrimary,
    Font = Enum.Font.GothamMedium,
    TextSize = 9,
    TextXAlignment = Enum.TextXAlignment.Left,
    Parent = PerformanceFrame
})

local lastFrameTime = tick()
local frameCount = 0

RunService.RenderStepped:Connect(function()
    frameCount = frameCount + 1
    if tick() - lastFrameTime >= 1 then
        local fps = frameCount
        FPSLabel.Text = "FPS: " .. tostring(fps)
        FPSLabel.TextColor3 = fps >= 55 and CONFIG.Colors.Success or fps >= 30 and CONFIG.Colors.Warning or CONFIG.Colors.Danger
        frameCount = 0
        lastFrameTime = tick()
    end
end)

-- INITIALIZATION
task.wait(0.4)
createNotification(
    "Mirage Hub Loaded",
    "Professional Edition v2.0.3 • Press Right Shift to toggle",
    3.5,
    "success"
)

debugPrint("Mirage Hub: Loaded (patched aura/esp)")

ScreenGui.Destroying:Connect(function()
    if pulseConnection then
        pulseConnection:Disconnect()
    end
    if auraConnection then
        auraConnection:Disconnect()
    end
    if espConnection then
        espConnection:Disconnect()
    end
    debugPrint("Mirage Hub: Unloaded successfully")
end)

-- END OF FILE
