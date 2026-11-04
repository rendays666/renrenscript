--[[
    SCRIPT DUMPER v13 — Runtime Capture + AI-Readable Config Snapshot
    Scan (safe) : baca .Source script dari root ON
    Runtime     : UI (watch PlayerGui) + HK (hook FireServer) + UC (unreliable fallback)
    Save        : SMART/FULL selalu include config snapshot + runtime capture

    FIX v13:
    - UI watcher tidak lagi mencatat tombol milik Dumper sendiri (spam log)
    - Nomor baris di API SURFACE / CLIENT HANDLERS sekarang akurat (baris kosong dihitung)
    - rebuildList tidak lagi menghasilkan baris ganda saat filter diketik cepat
    - Info chip bisa dibuka dengan tahan lama (mobile, tanpa klik kanan)
    - GUI diparent ke gethui() jika ada (fallback PlayerGui)
    - Guard typeof(self) di hook __namecall, guard oldIdx bukan function di UC
    - Filter core script ikut cek script itu sendiri (PlayerModule dkk)
    - Tombol SMART/FULL memberi peringatan kalau belum SCAN
    - tick() diganti os.clock()
]]

local Players     = game:GetService("Players")
local UIS         = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer
local PlayerGui   = LocalPlayer:WaitForChild("PlayerGui")

local function getGuiParent()
    if type(gethui) == "function" then
        local ok, h = pcall(gethui)
        if ok and typeof(h) == "Instance" then return h end
    end
    return PlayerGui
end
local GUI_PARENT = getGuiParent()

for _, p in ipairs({PlayerGui, GUI_PARENT}) do
    local old = p:FindFirstChild("ScriptDumperGui")
    if old then old:Destroy() end
end

-- ==========================================
-- CONSTANTS
-- ==========================================
local SCAN = {
    MAX_SCRIPT_SIZE   = 200 * 1024,
    MAX_TOTAL_MEM     = 10 * 1024 * 1024,
    ROOT_TIMEOUT      = 45,
    MAX_SCRIPTS_ROOT  = 800,
    BIG_LOG_THRESH    = 50 * 1024,
    RENDER_CAP        = 400,
}

local scanOptions = {
    decompile = false,
    bytecode  = false,
    readCore  = false,
}

local ROBLOX_CORE_NAMES = {
    PlayerModule = true, CameraModule = true, ControlModule = true,
    ChatScript = true, Chat = true, PlayerScriptsChat = true,
    Animate = true, Health = true, Sound = true,
    ClickToMove = true, ClassicCamera = true,
}

local scanAbort = false

-- ==========================================
-- GUI
-- ==========================================
local gui = Instance.new("ScreenGui")
gui.Name = "ScriptDumperGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 2147483647
gui.Parent = GUI_PARENT

local FULL_SIZE = UDim2.new(0, 240, 0, 350)
local MINI_SIZE = UDim2.new(0, 150, 0, 20)

local main = Instance.new("Frame")
main.Size = FULL_SIZE
main.Position = UDim2.new(0, 6, 0, 24)
main.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
main.BorderSizePixel = 0
main.Parent = gui
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 8)
local s1 = Instance.new("UIStroke", main)
s1.Color = Color3.fromRGB(80, 140, 255)
s1.Thickness = 1

local header = Instance.new("TextLabel")
header.Size = UDim2.new(1, -28, 0, 20)
header.BackgroundTransparency = 1
header.Text = "📜 Dumper v13"
header.Font = Enum.Font.GothamBold
header.TextSize = 11
header.TextColor3 = Color3.new(1,1,1)
header.TextXAlignment = Enum.TextXAlignment.Left
header.Parent = main
local hPad = Instance.new("UIPadding", header)
hPad.PaddingLeft = UDim.new(0, 6)

local minBtn = Instance.new("TextButton")
minBtn.Size = UDim2.new(0, 20, 0, 18)
minBtn.Position = UDim2.new(1, -22, 0, 1)
minBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 75)
minBtn.Text = "–"
minBtn.Font = Enum.Font.GothamBold
minBtn.TextSize = 14
minBtn.TextColor3 = Color3.new(1,1,1)
minBtn.Parent = main
Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0, 4)

local dragging, dragStart, startPos
header.InputBegan:Connect(function(input)
    if input.UserInputType ~= Enum.UserInputType.MouseButton1
    and input.UserInputType ~= Enum.UserInputType.Touch then return end
    dragging, dragStart, startPos = true, input.Position, main.Position
    local c
    c = input.Changed:Connect(function()
        if input.UserInputState == Enum.UserInputState.End then
            dragging = false c:Disconnect()
        end
    end)
end)
UIS.InputChanged:Connect(function(input)
    if not dragging then return end
    if input.UserInputType ~= Enum.UserInputType.MouseMovement
    and input.UserInputType ~= Enum.UserInputType.Touch then return end
    local d = input.Position - dragStart
    main.Position = UDim2.new(
        startPos.X.Scale, startPos.X.Offset + d.X,
        startPos.Y.Scale, startPos.Y.Offset + d.Y)
end)

-- TABS
local tabBar = Instance.new("Frame")
tabBar.Size = UDim2.new(1, -8, 0, 18)
tabBar.Position = UDim2.new(0, 4, 0, 20)
tabBar.BackgroundTransparency = 1
tabBar.Parent = main

local scanTabBtn = Instance.new("TextButton")
scanTabBtn.Size = UDim2.new(0.49, 0, 1, 0)
scanTabBtn.BackgroundColor3 = Color3.fromRGB(0, 140, 80)
scanTabBtn.Text = "SCAN"
scanTabBtn.Font = Enum.Font.GothamBold
scanTabBtn.TextSize = 9
scanTabBtn.TextColor3 = Color3.new(1,1,1)
scanTabBtn.Parent = tabBar
Instance.new("UICorner", scanTabBtn).CornerRadius = UDim.new(0, 4)

local logTabBtn = Instance.new("TextButton")
logTabBtn.Size = UDim2.new(0.49, 0, 1, 0)
logTabBtn.Position = UDim2.new(0.51, 0, 0, 0)
logTabBtn.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
logTabBtn.Text = "LOG"
logTabBtn.Font = Enum.Font.GothamBold
logTabBtn.TextSize = 9
logTabBtn.TextColor3 = Color3.new(1,1,1)
logTabBtn.Parent = tabBar
Instance.new("UICorner", logTabBtn).CornerRadius = UDim.new(0, 4)

local scanPanel = Instance.new("Frame")
scanPanel.Size = UDim2.new(1, 0, 1, -40)
scanPanel.Position = UDim2.new(0, 0, 0, 40)
scanPanel.BackgroundTransparency = 1
scanPanel.Parent = main

local logPanel = Instance.new("Frame")
logPanel.Size = UDim2.new(1, 0, 1, -40)
logPanel.Position = UDim2.new(0, 0, 0, 40)
logPanel.BackgroundTransparency = 1
logPanel.Visible = false
logPanel.Parent = main

local currentTab = "scan"
local function setTab(which)
    currentTab = which
    scanPanel.Visible = (which == "scan")
    logPanel.Visible  = (which == "log")
    scanTabBtn.BackgroundColor3 = (which == "scan")
        and Color3.fromRGB(0,140,80) or Color3.fromRGB(45,45,55)
    logTabBtn.BackgroundColor3 = (which == "log")
        and Color3.fromRGB(0,140,80) or Color3.fromRGB(45,45,55)
end
scanTabBtn.MouseButton1Click:Connect(function() setTab("scan") end)
logTabBtn.MouseButton1Click:Connect(function() setTab("log") end)

local minimized = false
minBtn.MouseButton1Click:Connect(function()
    minimized = not minimized
    if minimized then
        main.Size = MINI_SIZE
        tabBar.Visible = false
        scanPanel.Visible = false
        logPanel.Visible = false
        header.Text = "📜 D"
        minBtn.Text = "+"
    else
        main.Size = FULL_SIZE
        tabBar.Visible = true
        header.Text = "📜 Dumper v13"
        minBtn.Text = "–"
        setTab(currentTab)
    end
end)

-- ==========================================
-- LOG SYSTEM (must be first, used everywhere)
-- ==========================================
local logScroll = Instance.new("ScrollingFrame")
logScroll.Size = UDim2.new(1, -8, 1, -32)
logScroll.Position = UDim2.new(0, 4, 0, 0)
logScroll.BackgroundColor3 = Color3.fromRGB(8, 8, 12)
logScroll.BorderSizePixel = 0
logScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
logScroll.ScrollBarThickness = 3
logScroll.Parent = logPanel
Instance.new("UICorner", logScroll).CornerRadius = UDim.new(0, 5)

local logLayout = Instance.new("UIListLayout", logScroll)
logLayout.Padding = UDim.new(0, 1)
logLayout.SortOrder = Enum.SortOrder.LayoutOrder

local rtStatus = Instance.new("TextLabel")
rtStatus.Size = UDim2.new(1, -8, 0, 12)
rtStatus.Position = UDim2.new(0, 4, 1, -28)
rtStatus.BackgroundTransparency = 1
rtStatus.Text = "⏸ idle"
rtStatus.Font = Enum.Font.Code
rtStatus.TextSize = 8
rtStatus.TextColor3 = Color3.fromRGB(150, 200, 255)
rtStatus.TextXAlignment = Enum.TextXAlignment.Left
rtStatus.TextTruncate = Enum.TextTruncate.AtEnd
rtStatus.Parent = logPanel

local clearLogBtn = Instance.new("TextButton")
clearLogBtn.Size = UDim2.new(0.5, 0, 0, 12)
clearLogBtn.Position = UDim2.new(0.5, 0, 1, -14)
clearLogBtn.BackgroundColor3 = Color3.fromRGB(90, 40, 40)
clearLogBtn.Text = "CLR LOG"
clearLogBtn.Font = Enum.Font.GothamBold
clearLogBtn.TextSize = 8
clearLogBtn.TextColor3 = Color3.new(1,1,1)
clearLogBtn.Parent = logPanel
Instance.new("UICorner", clearLogBtn).CornerRadius = UDim.new(0, 3)

local MAX_LOG = 250
local logCount = 0

local function scanLog(text, color)
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -4, 0, 12)
    lbl.BackgroundTransparency = 1
    lbl.Text = tostring(text):sub(1, 160)
    lbl.Font = Enum.Font.Code
    lbl.TextSize = 8
    lbl.TextColor3 = color or Color3.fromRGB(180,180,180)
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.TextTruncate = Enum.TextTruncate.AtEnd
    lbl.Parent = logScroll
    logCount = logCount + 1
    if logCount > MAX_LOG then
        for _, c in ipairs(logScroll:GetChildren()) do
            if c:IsA("TextLabel") then c:Destroy() logCount = logCount - 1 break end
        end
    end
    logScroll.CanvasSize = UDim2.new(0, 0, 0, logCount * 13 + 4)
    logScroll.CanvasPosition = Vector2.new(0, math.max(0, logCount * 13 - 200))
end

local function setRtStatus(t, c)
    rtStatus.Text = t
    rtStatus.TextColor3 = c or Color3.fromRGB(150, 200, 255)
end

-- ==========================================
-- RUNTIME STATE
-- ==========================================
local uiActive = false
local hkActive = false
local ucActive = false
local uiConns  = {}
local namecallInstalled = false
local ucPatchedClasses  = {}

local runtimeCapture = {
    fireServer = {},
    ui         = {},
    log        = {},
}

local lastFS = {remote = nil, method = nil, time = 0}

local function safeClosure(fn)
    if type(newcclosure) == "function" then
        local ok, r = pcall(newcclosure, fn)
        if ok then return r end
    end
    return fn
end

-- --- UI WATCH ---
local function logButton(d)
    if not d or not d.Parent then return end
    if d:IsDescendantOf(gui) then return end -- FIX: jangan catat GUI Dumper sendiri
    local entry = {
        time = os.clock(),
        path = d:GetFullName(),
        class = d.ClassName,
        pos = tostring(d.AbsolutePosition),
        size = tostring(d.AbsoluteSize),
        text = (d:IsA("TextButton") and d.Text) or "",
        image = (d:IsA("ImageButton") and d.Image) or "",
        visible = d.Visible,
    }
    table.insert(runtimeCapture.ui, entry)
    if #runtimeCapture.ui > 300 then table.remove(runtimeCapture.ui, 1) end
    scanLog(("🖱 [UI] %s [%s] pos=%s size=%s%s%s")
        :format(entry.path, entry.class, entry.pos, entry.size,
            entry.text ~= "" and (" text=" .. entry.text:sub(1, 24)) or "",
            entry.image ~= "" and (" img=" .. entry.image:sub(1, 40)) or ""),
        Color3.fromRGB(100, 255, 200))
end

local function setUIWatch(state)
    if state == uiActive then return end
    uiActive = state
    if state then
        local pg = LocalPlayer:FindFirstChild("PlayerGui")
        if not pg then pg = LocalPlayer:WaitForChild("PlayerGui", 3) end
        if pg then
            for _, d in ipairs(pg:GetDescendants()) do
                if d:IsA("ImageButton") or d:IsA("TextButton") then
                    logButton(d)
                end
            end
            table.insert(uiConns, pg.DescendantAdded:Connect(function(d)
                if d:IsA("ImageButton") or d:IsA("TextButton") then
                    task.delay(0.15, function() logButton(d) end)
                end
            end))
            scanLog("[UI] ✓ watching PlayerGui", Color3.fromRGB(100,255,200))
        else
            scanLog("[UI] ✗ PlayerGui not found", Color3.fromRGB(255,100,100))
            uiActive = false
        end
    else
        for _, c in ipairs(uiConns) do pcall(function() c:Disconnect() end) end
        uiConns = {}
        scanLog("[UI] ✗ stopped", Color3.fromRGB(200,150,100))
    end
end

-- --- FIRESERVER LOG ---
local function logFS(remote, method, args)
    if typeof(remote) ~= "Instance" then return end
    local now = os.clock()
    if lastFS.remote == remote and lastFS.method == method
        and (now - lastFS.time) < 0.01 then return end
    lastFS.remote, lastFS.method, lastFS.time = remote, method, now

    local parts = {}
    for i = 1, math.min(args.n, 8) do
        local v = args[i]
        local tp = typeof(v)
        if tp == "Vector3" then
            parts[i] = ("V3(%0.1f,%0.1f,%0.1f)"):format(v.X, v.Y, v.Z)
        elseif tp == "CFrame" then
            parts[i] = ("CF(%0.1f,%0.1f,%0.1f)"):format(v.Position.X, v.Position.Y, v.Position.Z)
        elseif tp == "Instance" then
            parts[i] = "Inst:" .. tostring(v.Name):sub(1,20)
        elseif tp == "string" then
            parts[i] = string.format("%q", tostring(v):sub(1, 30))
        elseif tp == "number" or tp == "boolean" then
            parts[i] = tostring(v)
        else
            parts[i] = tp:sub(1, 3) .. ":" .. tostring(v):sub(1, 20)
        end
    end

    table.insert(runtimeCapture.fireServer, {
        time = now,
        remote = remote:GetFullName(),
        class = remote.ClassName,
        method = method,
        args = parts,
    })
    if #runtimeCapture.fireServer > 500 then
        table.remove(runtimeCapture.fireServer, 1)
    end

    scanLog(("🔥 %s %s(%s)"):format(method, remote.Name, table.concat(parts, ", ")),
        Color3.fromRGB(255, 200, 100))
end

-- --- HK (hook __namecall) ---
local function installHK()
    if namecallInstalled then return true end
    if type(hookmetamethod) ~= "function" or type(getnamecallmethod) ~= "function" then
        return false
    end
    local ok = pcall(function()
        local oldNamecall
        oldNamecall = hookmetamethod(game, "__namecall", safeClosure(function(self, ...)
            if hkActive then
                local method = getnamecallmethod()
                if (method == "FireServer" or method == "InvokeServer")
                    and typeof(self) == "Instance" then
                    local args = table.pack(...)
                    pcall(function() logFS(self, method, args) end)
                    -- getnamecallmethod bisa ter-reset; set ulang tidak perlu karena
                    -- kita lanjut lewat oldNamecall dengan self & args yang sama.
                end
            end
            return oldNamecall(self, ...)
        end))
    end)
    if ok then namecallInstalled = true return true end
    return false
end

-- --- UC (metatable per-class patch) ---
local function patchUC()
    if type(getrawmetatable) ~= "function" or type(setreadonly) ~= "function" then
        return false
    end
    local patched = 0
    for _, d in ipairs(game:GetDescendants()) do
        local cls = d.ClassName
        if (cls == "RemoteEvent" or cls == "RemoteFunction" or cls == "UnreliableRemoteEvent")
            and not ucPatchedClasses[cls] then
            pcall(function()
                local mt = getrawmetatable(d)
                if mt and type(mt.__index) == "function" and not mt.__dumperUCPatched then
                    local oldIdx = mt.__index
                    setreadonly(mt, false)
                    mt.__dumperUCPatched = true
                    mt.__index = safeClosure(function(self, key)
                        if ucActive and not hkActive
                            and (key == "FireServer" or key == "InvokeServer") then
                            local orig = oldIdx(self, key)
                            return safeClosure(function(_, ...)
                                local args = table.pack(...)
                                pcall(function() logFS(self, key, args) end)
                                return orig(self, ...)
                            end)
                        end
                        return oldIdx(self, key)
                    end)
                    setreadonly(mt, true)
                    ucPatchedClasses[cls] = true
                    patched = patched + 1
                end
            end)
        end
    end
    return patched > 0
end

-- ==========================================
-- TOOLTIP
-- ==========================================
local tooltipToken = 0
local tooltip = Instance.new("Frame")
tooltip.Size = UDim2.new(1, -16, 0, 90)
tooltip.Position = UDim2.new(0, 8, 1, -100)
tooltip.BackgroundColor3 = Color3.fromRGB(22, 22, 38)
tooltip.BorderSizePixel = 0
tooltip.Visible = false
tooltip.ZIndex = 50
tooltip.Parent = main
Instance.new("UICorner", tooltip).CornerRadius = UDim.new(0, 6)
local tStroke = Instance.new("UIStroke", tooltip)
tStroke.Color = Color3.fromRGB(100, 150, 255)
tStroke.Thickness = 1

local tTitle = Instance.new("TextLabel")
tTitle.Size = UDim2.new(1, -8, 0, 14)
tTitle.Position = UDim2.new(0, 4, 0, 2)
tTitle.BackgroundTransparency = 1
tTitle.Font = Enum.Font.GothamBold
tTitle.TextSize = 10
tTitle.TextColor3 = Color3.fromRGB(150, 200, 255)
tTitle.TextXAlignment = Enum.TextXAlignment.Left
tTitle.TextTruncate = Enum.TextTruncate.AtEnd
tTitle.ZIndex = 51
tTitle.Parent = tooltip

local tDesc = Instance.new("TextLabel")
tDesc.Size = UDim2.new(1, -8, 0, 30)
tDesc.Position = UDim2.new(0, 4, 0, 17)
tDesc.BackgroundTransparency = 1
tDesc.Font = Enum.Font.Gotham
tDesc.TextSize = 9
tDesc.TextColor3 = Color3.fromRGB(220, 220, 220)
tDesc.TextXAlignment = Enum.TextXAlignment.Left
tDesc.TextYAlignment = Enum.TextYAlignment.Top
tDesc.TextWrapped = true
tDesc.ZIndex = 51
tDesc.Parent = tooltip

local tUse = Instance.new("TextLabel")
tUse.Size = UDim2.new(1, -8, 0, 30)
tUse.Position = UDim2.new(0, 4, 0, 48)
tUse.BackgroundTransparency = 1
tUse.Font = Enum.Font.Gotham
tUse.TextSize = 9
tUse.TextColor3 = Color3.fromRGB(150, 255, 180)
tUse.TextXAlignment = Enum.TextXAlignment.Left
tUse.TextYAlignment = Enum.TextYAlignment.Top
tUse.TextWrapped = true
tUse.ZIndex = 51
tUse.Parent = tooltip

local tClose = Instance.new("TextButton")
tClose.Size = UDim2.new(0, 12, 0, 12)
tClose.Position = UDim2.new(1, -14, 0, 1)
tClose.BackgroundColor3 = Color3.fromRGB(80, 40, 40)
tClose.Text = "x"
tClose.Font = Enum.Font.GothamBold
tClose.TextSize = 9
tClose.TextColor3 = Color3.new(1,1,1)
tClose.BorderSizePixel = 0
tClose.ZIndex = 52
tClose.Parent = tooltip
Instance.new("UICorner", tClose).CornerRadius = UDim.new(1, 0)

local function hideTooltip()
    tooltipToken = tooltipToken + 1
    tooltip.Visible = false
end

local function showTooltip(info)
    tTitle.Text = info.name or "?"
    tDesc.Text = info.desc or ""
    tUse.Text = "💡 " .. (info.use or "")
    tooltip.Visible = true
    tooltipToken = tooltipToken + 1
    local t = tooltipToken
    task.delay(8, function()
        if tooltipToken == t then tooltip.Visible = false end
    end)
end
tClose.MouseButton1Click:Connect(hideTooltip)

-- Info via klik kanan (PC) ATAU tahan 0.5 detik (mobile)
local function attachInfo(btn, getInfo)
    btn.MouseButton2Click:Connect(function()
        local inf = getInfo()
        if inf then showTooltip(inf) end
    end)
    btn.InputBegan:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.Touch then return end
        local held = true
        local c
        c = input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                held = false
                c:Disconnect()
            end
        end)
        task.delay(0.5, function()
            if held then
                local inf = getInfo()
                if inf then showTooltip(inf) end
            end
        end)
    end)
end

local BTN_INFO = {
    SCAN  = {name="SCAN", desc="Scan .Source semua script dari root aktif.",
             use="Wajib. Tombol lain butuh hasil scan."},
    SMART = {name="SMART", desc="Build mechanics pack + save .txt (include config snapshot + runtime).",
             use="Arsip gameplay + request AI lain analisis."},
    MECH  = {name="MECH", desc="Build mechanics pack → clipboard.",
             use="Paste ke AI buat analisis gameplay cepat."},
    INDEX = {name="INDEX", desc="Daftar script + status.",
             use="Cek readable vs obf vs trunc."},
    FULL  = {name="FULL", desc="Save semua: config+index+mechanics+remotes+tree+runtime.",
             use="Backup lengkap ke repo pribadi."},
    CLR   = {name="CLR", desc="Clear list / abort scan.",
             use="Reset sebelum re-scan atau stop scan lambat."},
    REM   = {name="REM", desc="List RemoteEvent/RemoteFunction.",
             use="Lihat daftar remote yang dipakai game."},
    CFG   = {name="CFG", desc="Dump Value + Attributes.",
             use="Angka tuning (harga, cooldown, ratio)."},
    PATH  = {name="PATH", desc="Daftar full path semua script.",
             use="Copy path untuk referensi."},
    RUN   = {name="RUN", desc="Hook LogService + OnClientEvent (passive log).",
             use="Lihat error/warning + argumen server→client."},
    TREE  = {name="TREE", desc="Hierarchy service 2-3 level.",
             use="Mapping struktur game."},
}

local ROOT_INFO = {
    RS = {name="ReplicatedStorage", desc="Remote + ModuleScript shared.",
          use="Komunikasi client-server."},
    RF = {name="ReplicatedFirst", desc="Script loading awal.",
          use="Jalan sebelum game ready."},
    SP = {name="StarterPlayer", desc="Template LocalScript player.",
          use="Gerakan, camera, ability, input player."},
    SG = {name="StarterGui", desc="Template UI.",
          use="Struktur UI sebelum di-clone ke PlayerGui."},
    WS = {name="Workspace", desc="Map, model, NPC, Tool.",
          use="Paling banyak instance — lambat."},
    PL = {name="Players", desc="Player object + PlayerScripts runtime.",
          use="Script yang beneran jalan."},
    LT = {name="Lighting", desc="Efek visual, sky.", use="Jarang ada script."},
    SS = {name="SoundService", desc="Sound group.", use="Jarang ada script."},
    CH = {name="Chat", desc="TextChatService.", use="Audit command handler chat."},
    TM = {name="Teams", desc="Team container.", use="Cek team logic."},
}

local TOGGLE_INFO = {
    DC = {name="DC — Decompile Fallback",
          desc="Coba decompile() kalau .Source kosong. LAMBAT + crash-prone.",
          use="Aktifkan hanya untuk script spesifik yang source kosong."},
    BC = {name="BC — Bytecode Dump",
          desc="Bytecode mentah kalau decompile gagal. SANGAT besar.",
          use="Hanya untuk arsip — bytecode tidak terbaca."},
    RC = {name="RC — Read Roblox Core",
          desc="Ikut baca PlayerModule/CameraModule/ChatScript (≈300KB).",
          use="Hanya kalau butuh movement/camera code Roblox."},
    UI = {name="UI — Watch PlayerGui",
          desc="Rekam ImageButton/TextButton yang muncul di PlayerGui.",
          use="Cari nama tombol yang di-generate runtime."},
    HK = {name="HK — Hook FireServer",
          desc="Log argumen FireServer/InvokeServer via hookmetamethod (catch Unreliable juga).",
          use="Lihat isi argumen remote (origin, direction, weapon)."},
    UC = {name="UC — Unreliable Mode",
          desc="Patch metatable per-class (fallback kalau HK gagal catch).",
          use="Kalau RemoteEvent Unreliable lolos dari HK."},
    RT = {name="RT — Clear Runtime",
          desc="Hapus semua capture (UI + FireServer + Log).",
          use="Reset sebelum capture baru."},
}

-- ==========================================
-- BUTTONS
-- ==========================================
local function mkBtn(parent, text, x, w, y, color, ts, h)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(w, 0, 0, h or 18)
    b.Position = UDim2.new(x, 0, 0, y)
    b.BackgroundColor3 = color
    b.Text = text
    b.Font = Enum.Font.GothamBold
    b.TextSize = ts or 9
    b.TextColor3 = Color3.new(1,1,1)
    b.Parent = parent
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 4)
    return b
end

local function addInfoBadge(btn, key)
    local info = BTN_INFO[key]
    if not info then return end
    local q = Instance.new("TextButton")
    q.Size = UDim2.new(0, 10, 0, 10)
    q.Position = UDim2.new(1, -11, 0, 1)
    q.BackgroundColor3 = Color3.fromRGB(55, 55, 85)
    q.Text = "?"
    q.Font = Enum.Font.GothamBold
    q.TextSize = 8
    q.TextColor3 = Color3.fromRGB(140, 190, 255)
    q.BorderSizePixel = 0
    q.ZIndex = 5
    q.AutoButtonColor = false
    q.Parent = btn
    Instance.new("UICorner", q).CornerRadius = UDim.new(1, 0)
    q.MouseButton1Click:Connect(function() showTooltip(info) end)
end

local scanBtn  = mkBtn(scanPanel, "SCAN",  0.01, 0.32, 0, Color3.fromRGB(0,140,80), 9, 20)
local smartBtn = mkBtn(scanPanel, "SMART", 0.34, 0.32, 0, Color3.fromRGB(0,160,120), 9, 20)
local mechBtn  = mkBtn(scanPanel, "MECH",  0.67, 0.32, 0, Color3.fromRGB(40,140,200), 9, 20)
local idxBtn   = mkBtn(scanPanel, "INDEX", 0.01, 0.32, 22, Color3.fromRGB(60,100,160), 9)
local fullBtn  = mkBtn(scanPanel, "FULL",  0.34, 0.32, 22, Color3.fromRGB(80,80,80), 9)
local clrBtn   = mkBtn(scanPanel, "CLR",   0.67, 0.32, 22, Color3.fromRGB(120,50,50), 9)
local remBtn   = mkBtn(scanPanel, "REM",   0.01, 0.32, 42, Color3.fromRGB(140,60,140), 9)
local cfgBtn   = mkBtn(scanPanel, "CFG",   0.34, 0.32, 42, Color3.fromRGB(100,80,140), 9)
local pathBtn  = mkBtn(scanPanel, "PATH",  0.67, 0.32, 42, Color3.fromRGB(150,90,50), 9)
local runBtn   = mkBtn(scanPanel, "RUN",   0.01, 0.49, 62, Color3.fromRGB(200,120,40), 9)
local treeBtn  = mkBtn(scanPanel, "TREE",  0.51, 0.49, 62, Color3.fromRGB(60,80,140), 9)

addInfoBadge(scanBtn,"SCAN") addInfoBadge(smartBtn,"SMART") addInfoBadge(mechBtn,"MECH")
addInfoBadge(idxBtn,"INDEX") addInfoBadge(fullBtn,"FULL")   addInfoBadge(clrBtn,"CLR")
addInfoBadge(remBtn,"REM")   addInfoBadge(cfgBtn,"CFG")     addInfoBadge(pathBtn,"PATH")
addInfoBadge(runBtn,"RUN")   addInfoBadge(treeBtn,"TREE")

-- ==========================================
-- CHIP BAR (roots + options + runtime)
-- ==========================================
local SKIP_ROOTS = {
    {name="ReplicatedStorage", abbr="RS"},
    {name="ReplicatedFirst",   abbr="RF"},
    {name="StarterPlayer",     abbr="SP"},
    {name="StarterGui",        abbr="SG"},
    {name="Workspace",         abbr="WS"},
    {name="Players",           abbr="PL"},
    {name="Lighting",          abbr="LT"},
    {name="SoundService",      abbr="SS"},
    {name="Chat",              abbr="CH"},
    {name="Teams",             abbr="TM"},
}
local rootEnabled = {}
for _, r in ipairs(SKIP_ROOTS) do rootEnabled[r.name] = true end

local skipBar = Instance.new("ScrollingFrame")
skipBar.Size = UDim2.new(1, -8, 0, 16)
skipBar.Position = UDim2.new(0, 4, 0, 82)
skipBar.BackgroundColor3 = Color3.fromRGB(12, 12, 18)
skipBar.BorderSizePixel = 0
skipBar.CanvasSize = UDim2.new(0, 0, 0, 0)
skipBar.ScrollBarThickness = 2
skipBar.ScrollingDirection = Enum.ScrollingDirection.X
skipBar.Parent = scanPanel
Instance.new("UICorner", skipBar).CornerRadius = UDim.new(0, 3)

local skipLayout = Instance.new("UIListLayout", skipBar)
skipLayout.FillDirection = Enum.FillDirection.Horizontal
skipLayout.Padding = UDim.new(0, 2)
skipLayout.SortOrder = Enum.SortOrder.LayoutOrder
skipLayout.VerticalAlignment = Enum.VerticalAlignment.Center

for i, r in ipairs(SKIP_ROOTS) do
    local chip = Instance.new("TextButton")
    chip.Size = UDim2.new(0, 26, 0, 12)
    chip.BackgroundColor3 = Color3.fromRGB(0, 140, 80)
    chip.Text = r.abbr
    chip.Font = Enum.Font.GothamBold
    chip.TextSize = 8
    chip.TextColor3 = Color3.new(1,1,1)
    chip.BorderSizePixel = 0
    chip.LayoutOrder = i
    chip.Parent = skipBar
    Instance.new("UICorner", chip).CornerRadius = UDim.new(0, 3)
    chip.MouseButton1Click:Connect(function()
        rootEnabled[r.name] = not rootEnabled[r.name]
        chip.BackgroundColor3 = rootEnabled[r.name]
            and Color3.fromRGB(0, 140, 80) or Color3.fromRGB(80, 40, 40)
    end)
    attachInfo(chip, function()
        local inf = ROOT_INFO[r.abbr]
        if not inf then return nil end
        return { name = r.abbr .. " = " .. inf.name, desc = inf.desc, use = inf.use }
    end)
end

-- Toggle chip builder
local function mkToggleChip(abbr, isOn, onToggle, layoutOrder)
    local chip = Instance.new("TextButton")
    chip.Size = UDim2.new(0, 22, 0, 12)
    chip.BackgroundColor3 = isOn()
        and Color3.fromRGB(0, 140, 80) or Color3.fromRGB(80, 40, 40)
    chip.Text = abbr
    chip.Font = Enum.Font.GothamBold
    chip.TextSize = 8
    chip.TextColor3 = Color3.new(1,1,1)
    chip.BorderSizePixel = 0
    chip.LayoutOrder = layoutOrder
    chip.Parent = skipBar
    Instance.new("UICorner", chip).CornerRadius = UDim.new(0, 3)
    local function refresh()
        chip.BackgroundColor3 = isOn()
            and Color3.fromRGB(0, 140, 80) or Color3.fromRGB(80, 40, 40)
    end
    chip.MouseButton1Click:Connect(function()
        onToggle()
        refresh()
    end)
    attachInfo(chip, function() return TOGGLE_INFO[abbr] end)
    return chip
end

-- Options DC/BC/RC
mkToggleChip("DC", function() return scanOptions.decompile end,
    function() scanOptions.decompile = not scanOptions.decompile end, 100)
mkToggleChip("BC", function() return scanOptions.bytecode end,
    function() scanOptions.bytecode = not scanOptions.bytecode end, 101)
mkToggleChip("RC", function() return scanOptions.readCore end,
    function() scanOptions.readCore = not scanOptions.readCore end, 102)

-- Runtime UI / HK / UC / RT
mkToggleChip("UI", function() return uiActive end,
    function() setUIWatch(not uiActive) end, 200)

mkToggleChip("HK", function() return hkActive end, function()
    if not hkActive then
        local ok = installHK()
        if not ok then
            scanLog("[HK] ✗ hookmetamethod tidak tersedia", Color3.fromRGB(255,100,100))
            return
        end
    end
    hkActive = not hkActive
    scanLog("[HK] " .. (hkActive and "✓ aktif" or "✗ mati"), Color3.fromRGB(200,200,255))
end, 201)

mkToggleChip("UC", function() return ucActive end, function()
    ucActive = not ucActive
    if ucActive then
        local ok = patchUC()
        scanLog("[UC] " .. (ok and "✓ patched" or "⚠ patch gagal / sudah ter-patch"),
            ok and Color3.fromRGB(200,200,255) or Color3.fromRGB(255,200,100))
    else
        scanLog("[UC] ✗ mati", Color3.fromRGB(200,150,100))
    end
end, 202)

mkToggleChip("RT", function() return false end, function()
    runtimeCapture.fireServer = {}
    runtimeCapture.ui = {}
    runtimeCapture.log = {}
    scanLog("[RT] runtime cleared", Color3.fromRGB(200,150,100))
end, 203)

skipLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    skipBar.CanvasSize = UDim2.new(0, skipLayout.AbsoluteContentSize.X + 8, 0, 0)
end)

-- Filter
local filterBox = Instance.new("TextBox")
filterBox.Size = UDim2.new(0.96, 0, 0, 16)
filterBox.Position = UDim2.new(0.02, 0, 0, 100)
filterBox.BackgroundColor3 = Color3.fromRGB(30, 30, 38)
filterBox.BorderSizePixel = 0
filterBox.PlaceholderText = "Filter path…"
filterBox.Text = ""
filterBox.ClearTextOnFocus = false
filterBox.Font = Enum.Font.Gotham
filterBox.TextSize = 9
filterBox.TextColor3 = Color3.new(1,1,1)
filterBox.PlaceholderColor3 = Color3.fromRGB(120,120,120)
filterBox.Parent = scanPanel
Instance.new("UICorner", filterBox).CornerRadius = UDim.new(0, 4)

local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.new(1, -8, 0, 178)
scroll.Position = UDim2.new(0, 4, 0, 118)
scroll.BackgroundColor3 = Color3.fromRGB(8, 8, 12)
scroll.BorderSizePixel = 0
scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
scroll.ScrollBarThickness = 4
scroll.Parent = scanPanel
Instance.new("UICorner", scroll).CornerRadius = UDim.new(0, 5)

local layout = Instance.new("UIListLayout", scroll)
layout.Padding = UDim.new(0, 1)
layout.SortOrder = Enum.SortOrder.LayoutOrder

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -8, 0, 12)
status.Position = UDim2.new(0, 4, 1, -14)
status.BackgroundTransparency = 1
status.Text = "Ready."
status.Font = Enum.Font.Gotham
status.TextSize = 9
status.TextColor3 = Color3.fromRGB(180,180,180)
status.TextXAlignment = Enum.TextXAlignment.Left
status.Parent = scanPanel

-- ==========================================
-- LOGIC STATE
-- ==========================================
local allScripts    = {}
local bigScripts    = {}
local scanRunning   = false
local filterToken   = 0
local renderToken   = 0
local runtimeActive = false
local runtimeConns  = {}

local MECHANIC_KW = {
    "damage","health","hit","attack","weapon","kill","death","respawn",
    "shield","armor","dmg","crit","swing","punch",
    "coin","cash","money","currency","gem","gold","shop","buy","purchase",
    "price","cost","sell","reward","drop","loot","chest",
    "xp","level","rank","exp","progress","unlock","upgrade","tier",
    "quest","mission","achievement","badge",
    "item","inventory","tool","gear","equip",
    "speed","jump","walk","run","sprint","stamina","dash","ability",
    "skill","power","cooldown","boost",
    "spawn","teleport","zone","area","map","portal","gate","round",
    "match","team","score","point","leaderboard","stat","win","lose",
    "save","load","data","profile","session",
    "ui","gui","menu","button","hud","notification",
}

local TYPE_COLOR = {
    LocalScript  = Color3.fromRGB(120, 200, 255),
    ModuleScript = Color3.fromRGB(255, 200, 100),
    Script       = Color3.fromRGB(255, 130, 130),
}

local STATUS_COLOR = {
    readable  = Color3.fromRGB(140, 220, 140),
    empty     = Color3.fromRGB(160, 160, 160),
    obf       = Color3.fromRGB(255, 180, 80),
    bcode     = Color3.fromRGB(200, 130, 255),
    truncated = Color3.fromRGB(255, 220, 90),
    skipped   = Color3.fromRGB(120, 120, 120),
}

-- ==========================================
-- HELPERS
-- ==========================================
local function copyText(text, label)
    local fn = setclipboard or writeclipboard or toclipboard
    if not fn then status.Text = "✗ No clipboard" return end
    local ok = pcall(function() fn(text) end)
    status.Text = ok
        and ("✓ %s (%d char)"):format(label, #text)
        or  "✗ Copy failed"
end

local function getWorkspacePath()
    if type(getworkspace) == "function" then
        local ok, p = pcall(getworkspace)
        if ok and type(p) == "string" then return p end
    end
    return "workspace (folder executor)"
end

-- FIX: cek script itu sendiri + ancestor
local function hasCoreAncestor(inst, depth)
    depth = depth or 5
    if ROBLOX_CORE_NAMES[inst.Name] then return inst.Name end
    local p, i = inst.Parent, 0
    while p and i < depth do
        if ROBLOX_CORE_NAMES[p.Name] then return p.Name end
        p, i = p.Parent, i + 1
    end
    return nil
end

local function readSource(inst, maxBytes)
    local ok, raw = pcall(function() return inst.Source end)
    if ok and type(raw) == "string" and #raw > 0 then
        local size = #raw
        if size > maxBytes then
            raw = raw:sub(1, maxBytes) .. "\n-- [TRUNC " .. (size - maxBytes) .. "b]"
            return raw, "truncated", size
        end
        return raw, "src", size
    end
    if scanOptions.decompile and type(decompile) == "function" then
        local ok2, dec = pcall(decompile, inst)
        if ok2 and type(dec) == "string" and #dec > 0 then
            local size = #dec
            if size > maxBytes then
                dec = dec:sub(1, maxBytes) .. "\n-- [TRUNC " .. (size - maxBytes) .. "b]"
                return dec, "truncated", size
            end
            return dec, "src", size
        end
    end
    if scanOptions.bytecode and type(getscriptbytecode) == "function" then
        local ok3, bc = pcall(getscriptbytecode, inst)
        if ok3 and type(bc) == "string" and #bc > 0 then
            return "-- [BYTECODE " .. #bc .. "b]\n" .. bc:sub(1, 500), "bcode", #bc
        end
    end
    return nil, nil, 0
end

local function getGameName()
    local ok, info = pcall(function()
        return game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId)
    end)
    return (ok and info and info.Name) or "Unknown"
end

local function extractFunctions(src, maxBlock)
    maxBlock = maxBlock or 200
    local lines = {}
    for line in (src .. "\n"):gmatch("([^\n]*)\n") do table.insert(lines, line) end
    local funcs, i = {}, 1
    while i <= #lines do
        local line = lines[i]
        local fnName =
            line:match("^%s*local%s+function%s+([%w_%.]+)") or
            line:match("^%s*function%s+([%w_%.:]+)") or
            line:match("^%s*local%s+([%w_]+)%s*=%s*function")
        if fnName then
            local body, j = { line }, i + 1
            while j <= #lines and #body < maxBlock do
                local nl = lines[j]
                if nl:match("^%s*local%s+function%s+") or
                   nl:match("^%s*function%s+") or
                   nl:match("^%s*local%s+[%w_]+%s*=%s*function") then break end
                table.insert(body, nl); j = j + 1
            end
            table.insert(funcs, { name = fnName, body = table.concat(body, "\n") })
            i = j
        else i = i + 1 end
    end
    return funcs
end

local function countLines(s)
    local n = 1
    for _ in s:gmatch("\n") do n = n + 1 end
    return n
end

-- FIX: iterasi baris dengan nomor baris yang benar (baris kosong ikut dihitung)
local function eachLine(src)
    local n = 0
    return function()
        return nil
    end, src, n
end

local function findLines(src, matcher, maxLen)
    local hits, n = {}, 0
    for line in (src .. "\n"):gmatch("([^\n]*)\n") do
        n = n + 1
        if matcher(line) then
            table.insert(hits, ("    L%d: %s"):format(n, line:sub(1, maxLen or 120)))
        end
    end
    return hits
end

-- ==========================================
-- CONFIG SNAPSHOT (untuk AI lain baca)
-- ==========================================
local function buildConfigSnapshot()
    local out = {}
    local sep = string.rep("=", 62)
    table.insert(out, sep)
    table.insert(out, "DUMPER v13 — CONFIG SNAPSHOT (untuk AI analyst)")
    table.insert(out, sep)
    table.insert(out, "Game      : " .. getGameName())
    table.insert(out, "PlaceId   : " .. tostring(game.PlaceId))
    table.insert(out, "JobId     : " .. tostring(game.JobId))
    table.insert(out, "Player    : " .. LocalPlayer.Name)
    table.insert(out, "Generated : " .. os.date("%Y-%m-%d %H:%M:%S"))
    table.insert(out, "")
    table.insert(out, "──────────────────────────────────────────")
    table.insert(out, "MEKANISME DUMPER (baca dulu):")
    table.insert(out, "──────────────────────────────────────────")
    table.insert(out, "1. SCAN         → baca .Source semua script dari root yang ON")
    table.insert(out, "                  (bukan runtime, hanya snapshot statis dari kode)")
    table.insert(out, "2. SMART/FULL   → build analisis pakai hasil scan")
    table.insert(out, "3. UI/HK/UC     → rekam data RUNTIME terpisah dari scan")
    table.insert(out, "4. Chip RS..TM  → pilih root mana yang di-scan")
    table.insert(out, "5. Chip DC/BC/RC→ opsi baca source (default OFF untuk anti-crash)")
    table.insert(out, "6. Chip UI/HK/UC→ rekam aktivitas live (butuh diaktifkan user)")
    table.insert(out, "")
    table.insert(out, "──────────────────────────────────────────")
    table.insert(out, "ROOT SCAN (chip RS..TM):")
    table.insert(out, "──────────────────────────────────────────")
    for _, r in ipairs(SKIP_ROOTS) do
        local inf = ROOT_INFO[r.abbr]
        table.insert(out, ("  [%s] %s  %-18s — %s")
            :format(rootEnabled[r.name] and "ON " or "OFF",
                r.abbr, inf and inf.name or r.name, inf and inf.desc or ""))
    end
    table.insert(out, "")
    table.insert(out, "──────────────────────────────────────────")
    table.insert(out, "OPSI SCAN (chip DC/BC/RC):")
    table.insert(out, "──────────────────────────────────────────")
    table.insert(out, ("  [%s] DC  Decompile fallback (LAMBAT, crash-prone)")
        :format(scanOptions.decompile and "ON " or "OFF"))
    table.insert(out, ("  [%s] BC  Bytecode dump (SANGAT besar, tak terbaca)")
        :format(scanOptions.bytecode and "ON " or "OFF"))
    table.insert(out, ("  [%s] RC  Read Roblox core (PlayerModule/CameraModule dkk)")
        :format(scanOptions.readCore and "ON " or "OFF"))
    table.insert(out, "")
    table.insert(out, "──────────────────────────────────────────")
    table.insert(out, "RUNTIME CAPTURE (chip UI/HK/UC):")
    table.insert(out, "──────────────────────────────────────────")
    table.insert(out, ("  [%s] UI  Watch PlayerGui (ImageButton/TextButton muncul)")
        :format(uiActive and "ON " or "OFF"))
    table.insert(out, ("  [%s] HK  Hook FireServer/InvokeServer (log argumen)")
        :format(hkActive and "ON " or "OFF"))
    table.insert(out, ("  [%s] UC  Unreliable mode (patch metatable fallback)")
        :format(ucActive and "ON " or "OFF"))
    table.insert(out, "")
    table.insert(out, "──────────────────────────────────────────")
    table.insert(out, "BUTTON LIST:")
    table.insert(out, "──────────────────────────────────────────")
    for _, key in ipairs({"SCAN","SMART","MECH","INDEX","FULL","CLR",
                          "REM","CFG","PATH","RUN","TREE"}) do
        local inf = BTN_INFO[key]
        table.insert(out, ("  %-5s — %s"):format(key, inf.desc))
    end
    table.insert(out, "")
    table.insert(out, "──────────────────────────────────────────")
    table.insert(out, "STATISTIK DATA:")
    table.insert(out, "──────────────────────────────────────────")
    local r,e,o,b,t = 0,0,0,0,0
    for _, s in ipairs(allScripts) do
        if s.status == "readable" then r = r + 1
        elseif s.status == "empty" then e = e + 1
        elseif s.status == "obf" then o = o + 1
        elseif s.status == "bcode" then b = b + 1
        elseif s.status == "truncated" then t = t + 1 end
    end
    table.insert(out, ("  Scripts total      : %d (readable=%d empty=%d obf=%d bcode=%d trunc=%d)")
        :format(#allScripts, r, e, o, b, t))
    table.insert(out, ("  Runtime UI         : %d tombol tercatat")
        :format(#runtimeCapture.ui))
    table.insert(out, ("  Runtime FireServer : %d call tercatat")
        :format(#runtimeCapture.fireServer))
    table.insert(out, ("  Runtime LogService : %d pesan")
        :format(#runtimeCapture.log))
    table.insert(out, "")
    table.insert(out, "──────────────────────────────────────────")
    table.insert(out, "DATA APA YANG TERSEDIA DI FILE INI:")
    table.insert(out, "──────────────────────────────────────────")
    table.insert(out, ("  ✅ Script source   : %d readable script"):format(r))
    table.insert(out, "  ✅ Mechanics pack  : API/Handlers/Modules/Constants")
    table.insert(out, "  ✅ Remotes         : RemoteEvent/RemoteFunction list")
    if #runtimeCapture.ui > 0 then
        table.insert(out, ("  ✅ Runtime UI      : %d tombol"):format(#runtimeCapture.ui))
    else
        table.insert(out, "  ❌ Runtime UI      : kosong (chip UI belum diaktifkan / belum buka menu)")
    end
    if #runtimeCapture.fireServer > 0 then
        table.insert(out, ("  ✅ Runtime FS      : %d call"):format(#runtimeCapture.fireServer))
    else
        table.insert(out, "  ❌ Runtime FS      : kosong (HK/UC belum diaktifkan / belum ada aksi)")
    end
    table.insert(out, "")
    table.insert(out, "──────────────────────────────────────────")
    table.insert(out, "INSTRUKSI UNTUK AI LAIN:")
    table.insert(out, "──────────────────────────────────────────")
    table.insert(out, "  - Cek daftar ON/OFF di atas sebelum analisis")
    table.insert(out, "  - Data yang ditandai ❌ = tidak ada di file ini")
    table.insert(out, "  - Kalau butuh data yang OFF, minta user:")
    table.insert(out, "      • untuk PlayerModule → aktifkan chip RC + re-SCAN")
    table.insert(out, "      • untuk tombol runtime → aktifkan chip UI, buka menu/match, baru capture")
    table.insert(out, "      • untuk argumen remote → aktifkan chip HK (atau UC), lakukan aksi sekali")
    table.insert(out, "  - Runtime capture TIDAK butuh SCAN ulang, cukup aktifkan chip")
    table.insert(out, "  - Kalau user minta data yang 'penting saja', saran:")
    table.insert(out, "      • Script logic  → RS + SP saja (skip WS/PL/SG)")
    table.insert(out, "      • Runtime UI    → UI on, buka menu")
    table.insert(out, "      • Argumen remote→ HK on (atau UC on), lakukan aksi sekali")
    table.insert(out, sep)
    return table.concat(out, "\n")
end

-- ==========================================
-- RUNTIME SECTION BUILDER
-- ==========================================
local function buildRuntimeSection()
    local sep = string.rep("=", 62)
    local out = { sep, "RUNTIME CAPTURE", sep }

    if #runtimeCapture.ui == 0 and #runtimeCapture.fireServer == 0 then
        table.insert(out, "")
        table.insert(out, "⚠ Tidak ada runtime capture.")
        table.insert(out, "  Untuk UI  : aktifkan chip UI → buka menu")
        table.insert(out, "  Untuk FS  : aktifkan chip HK → lakukan aksi sekali")
    end

    if #runtimeCapture.ui > 0 then
        table.insert(out, "")
        table.insert(out, ("## UI — %d tombol (ImageButton/TextButton)"):format(#runtimeCapture.ui))
        for i, e in ipairs(runtimeCapture.ui) do
            table.insert(out, ("[%d] %s [%s]")
                :format(i, e.path, e.class))
            table.insert(out, ("     pos=%s size=%s visible=%s")
                :format(e.pos, e.size, tostring(e.visible)))
            if e.text ~= "" then
                table.insert(out, ("     text=%q"):format(e.text:sub(1, 40)))
            end
            if e.image ~= "" then
                table.insert(out, ("     image=%s"):format(e.image:sub(1, 80)))
            end
        end
    end

    if #runtimeCapture.fireServer > 0 then
        table.insert(out, "")
        table.insert(out, ("## FireServer/InvokeServer — %d call"):format(#runtimeCapture.fireServer))
        table.insert(out, "  Format: [n] Method Remote(args) — arg tipe+isi")
        for i, e in ipairs(runtimeCapture.fireServer) do
            table.insert(out, ("[%d] %s %s(%s)")
                :format(i, e.method, e.remote, table.concat(e.args, ", ")))
        end
        table.insert(out, "")
        table.insert(out, "  💡 Analisis: argumen Vector3/CFrame = posisi/arah, string = nama aksi/item.")
    end

    if #runtimeCapture.log > 0 then
        table.insert(out, "")
        table.insert(out, ("## LogService — %d pesan"):format(#runtimeCapture.log))
        for i, e in ipairs(runtimeCapture.log) do
            table.insert(out, ("[%d] [%s] %s"):format(i, e.type, e.msg))
        end
    end

    table.insert(out, sep)
    return table.concat(out, "\n")
end

-- ==========================================
-- BUILDERS (index/remotes/tree/config/mechanics)
-- ==========================================
local function buildIndex()
    local out = { string.rep("=",60), "SCRIPT INDEX", string.rep("=",60),
        "Game    : " .. getGameName(),
        "PlaceId : " .. tostring(game.PlaceId),
        "JobId   : " .. tostring(game.JobId),
        "Total   : " .. #allScripts, "" }
    local sorted = {}
    for _, s in ipairs(allScripts) do table.insert(sorted, s) end
    table.sort(sorted, function(a, b) return a.path < b.path end)
    for i, s in ipairs(sorted) do
        table.insert(out, ("[%d/%d] %s | %s | %dB | %s")
            :format(i, #sorted, s.class, s.status, s.size, s.path))
    end
    return table.concat(out, "\n")
end

local function isRemoteInstance(d)
    if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") then return true end
    local ok, res = pcall(function() return d:IsA("UnreliableRemoteEvent") end)
    return ok and res == true
end

local function buildRemotes()
    local out = { "=== REMOTES ===" }
    for _, d in ipairs(game:GetDescendants()) do
        if isRemoteInstance(d) then
            table.insert(out, ("[%s] %s"):format(d.ClassName, d:GetFullName()))
        end
    end
    return table.concat(out, "\n")
end

local function buildTree()
    local out = { "=== STRUCTURE TREE ===" }
    local services = {"ReplicatedStorage","ReplicatedFirst","StarterPlayer",
        "StarterGui","Workspace","Players","Lighting"}
    local function tagOf(i)
        if i:IsA("LocalScript") or i:IsA("ModuleScript") or i:IsA("Script") then
            return " *"
        elseif i:IsA("RemoteEvent") or i:IsA("RemoteFunction") then return " !" end
        return ""
    end
    for _, name in ipairs(services) do
        local svc = game:FindFirstChild(name)
        if svc then
            table.insert(out, ""); table.insert(out, "[" .. name .. "]")
            local ok, lvl1 = pcall(function() return svc:GetChildren() end)
            if ok and lvl1 then
                for _, c1 in ipairs(lvl1) do
                    table.insert(out, ("  %s [%s]%s"):format(c1.Name, c1.ClassName, tagOf(c1)))
                    if c1:IsA("Folder") or c1:IsA("Model") then
                        local ok2, lvl2 = pcall(function() return c1:GetChildren() end)
                        if ok2 and lvl2 then
                            for _, c2 in ipairs(lvl2) do
                                table.insert(out, ("    %s [%s]%s"):format(c2.Name, c2.ClassName, tagOf(c2)))
                            end
                        end
                    end
                end
            end
        end
    end
    table.insert(out, "\nLegend: * = script, ! = remote")
    return table.concat(out, "\n")
end

local function buildConfig()
    local out = { "=== VALUES ===" }
    local valueRoots = {}
    for _, n in ipairs({"ReplicatedStorage","Workspace","Lighting","StarterPlayer"}) do
        local ok, svc = pcall(function() return game:GetService(n) end)
        if ok and svc then table.insert(valueRoots, svc) end
    end
    for _, root in ipairs(valueRoots) do
        for _, d in ipairs(root:GetDescendants()) do
            local cls = d.ClassName
            if cls == "StringValue" or cls == "NumberValue"
            or cls == "BoolValue" or cls == "IntValue" or cls == "ObjectValue" then
                local v
                if cls == "StringValue" then v = '"' .. tostring(d.Value):sub(1,80) .. '"'
                elseif cls == "ObjectValue" then v = d.Value and d.Value:GetFullName() or "nil"
                else v = tostring(d.Value) end
                table.insert(out, ("[%s] %s = %s"):format(cls, d:GetFullName(), v))
            end
        end
    end
    table.insert(out, "\n=== ATTRIBUTES ===")
    for i = 1, math.min(3, #valueRoots) do
        local root = valueRoots[i]
        for _, d in ipairs(root:GetDescendants()) do
            local ok, attrs = pcall(function() return d:GetAttributes() end)
            if ok and attrs and next(attrs) then
                local p = {}
                for k, v in pairs(attrs) do table.insert(p, k .. "=" .. tostring(v)) end
                table.insert(out, ("[Attr] %s: {%s}")
                    :format(d:GetFullName(), table.concat(p, ", ")))
            end
        end
    end
    return table.concat(out, "\n")
end

local function buildMechanics()
    local parts = {}
    local sep = string.rep("=", 60)
    table.insert(parts, sep); table.insert(parts, "GAME MECHANICS ANALYSIS")
    table.insert(parts, sep)
    table.insert(parts, "Game      : " .. getGameName())
    table.insert(parts, "PlaceId   : " .. tostring(game.PlaceId))
    table.insert(parts, "JobId     : " .. tostring(game.JobId))
    table.insert(parts, "Player    : " .. LocalPlayer.Name)
    table.insert(parts, "UserId    : " .. tostring(LocalPlayer.UserId))
    table.insert(parts, "Generated : " .. os.date("%Y-%m-%d %H:%M:%S"))

    local readable, empty, obf, bc, trunc = 0, 0, 0, 0, 0
    for _, s in ipairs(allScripts) do
        if s.status == "readable" then readable = readable + 1
        elseif s.status == "empty" then empty = empty + 1
        elseif s.status == "obf" then obf = obf + 1
        elseif s.status == "bcode" then bc = bc + 1
        elseif s.status == "truncated" then trunc = trunc + 1 end
    end
    table.insert(parts, ("Scripts   : %d (readable=%d empty=%d obf=%d bcode=%d trunc=%d)")
        :format(#allScripts, readable, empty, obf, bc, trunc))
    table.insert(parts, "")

    table.insert(parts, sep); table.insert(parts, "## 1. API SURFACE")
    table.insert(parts, sep); table.insert(parts, "")
    local apiCount = 0
    for _, s in ipairs(allScripts) do
        if s.src then
            local calls = findLines(s.src, function(line)
                return line:find(":FireServer", 1, true) or line:find(":InvokeServer", 1, true)
            end)
            if #calls > 0 then
                apiCount = apiCount + #calls
                table.insert(parts, "")
                table.insert(parts, ("[%s] %s"):format(s.class, s.path))
                for _, c in ipairs(calls) do table.insert(parts, c) end
            end
        end
    end
    table.insert(parts, "")
    table.insert(parts, ("─── Total: %d remote calls ───"):format(apiCount))

    table.insert(parts, "")
    table.insert(parts, sep); table.insert(parts, "## 2. CLIENT HANDLERS")
    table.insert(parts, sep); table.insert(parts, "")
    local hCount = 0
    for _, s in ipairs(allScripts) do
        if s.src then
            local handlers = findLines(s.src, function(line)
                return line:find("OnClientEvent", 1, true)
                    or line:find("GetPropertyChangedSignal", 1, true)
            end)
            if #handlers > 0 then
                hCount = hCount + #handlers
                table.insert(parts, "")
                table.insert(parts, ("[%s] %s"):format(s.class, s.path))
                for _, h in ipairs(handlers) do table.insert(parts, h) end
            end
        end
    end
    table.insert(parts, "")
    table.insert(parts, ("─── Total: %d handler ───"):format(hCount))

    table.insert(parts, "")
    table.insert(parts, sep); table.insert(parts, "## 3. MODULES")
    table.insert(parts, sep); table.insert(parts, "")
    local modCount = 0
    for _, s in ipairs(allScripts) do
        if s.class == "ModuleScript" and s.src then
            modCount = modCount + 1
            local funcs = extractFunctions(s.src, 999)
            local names = {}
            for _, f in ipairs(funcs) do table.insert(names, f.name) end
            table.insert(parts, ("[Module] %s"):format(s.path))
            table.insert(parts, ("  size=%dB  lines=%d  method=%s")
                :format(s.size, countLines(s.src), s.how or "?"))
            if #names > 0 then
                table.insert(parts, "  funcs: " .. table.concat(names, ", ", 1, math.min(25,#names)))
            end
            table.insert(parts, "")
        end
    end
    table.insert(parts, ("─── Total: %d modules ───"):format(modCount))

    table.insert(parts, "")
    table.insert(parts, sep); table.insert(parts, "## 4. CONSTANTS")
    table.insert(parts, sep); table.insert(parts, "")
    table.insert(parts, buildConfig())

    table.insert(parts, "")
    table.insert(parts, sep); table.insert(parts, "## 5. TOP 15 BIG SCRIPT")
    table.insert(parts, sep); table.insert(parts, "")
    local top = {}
    for _, s in ipairs(allScripts) do if s.src then table.insert(top, s) end end
    table.sort(top, function(a,b) return a.size > b.size end)
    for i = 1, math.min(15, #top) do
        local s = top[i]
        table.insert(parts, ("[%d] [%s] %s — %dB / %d lines")
            :format(i, s.class, s.path, s.size, countLines(s.src)))
    end

    table.insert(parts, "")
    table.insert(parts, sep); table.insert(parts, "## 6. MECHANIC HITS")
    table.insert(parts, sep); table.insert(parts, "")
    local groups = {}
    for _, s in ipairs(allScripts) do
        if s.src then
            local lower = s.path:lower()
            for _, kw in ipairs(MECHANIC_KW) do
                if lower:find(kw, 1, true) then
                    groups[kw] = groups[kw] or {}
                    table.insert(groups[kw], s); break
                end
            end
        end
    end
    local kws = {}
    for k in pairs(groups) do table.insert(kws, k) end
    table.sort(kws)
    for _, kw in ipairs(kws) do
        table.insert(parts, "")
        table.insert(parts, ("### " .. kw:upper() .. " (" .. #groups[kw] .. ")"))
        for _, s in ipairs(groups[kw]) do
            table.insert(parts, ("  [%s] %s (%dB)"):format(s.status, s.path, s.size))
        end
    end

    table.insert(parts, "")
    table.insert(parts, sep)
    table.insert(parts, "END OF MECHANICS")
    table.insert(parts, sep)
    return table.concat(parts, "\n")
end

-- ==========================================
-- LIST RENDER
-- ==========================================
local function clearList()
    for _, c in ipairs(scroll:GetChildren()) do
        if c:IsA("TextButton") then c:Destroy() end
    end
end

local function rebuildList()
    clearList()
    renderToken = renderToken + 1          -- FIX: batalkan render lama yang masih jalan
    local myToken = renderToken
    local filter = filterBox.Text:lower()
    local shown, batch, capped = 0, 0, false
    task.spawn(function()
        for _, s in ipairs(allScripts) do
            if myToken ~= renderToken then return end
            if shown >= SCAN.RENDER_CAP then capped = true break end
            if filter == "" or s.path:lower():find(filter, 1, true) then
                shown = shown + 1
                local row = Instance.new("TextButton")
                row.Size = UDim2.new(1, -4, 0, 18)
                row.BackgroundColor3 = Color3.fromRGB(22, 22, 30)
                row.BorderSizePixel = 0
                row.Text = ""
                row.AutoButtonColor = false
                row.Parent = scroll

                local tag = Instance.new("TextLabel")
                tag.Size = UDim2.new(0, 34, 1, 0)
                tag.BackgroundColor3 = TYPE_COLOR[s.class] or Color3.fromRGB(100,100,100)
                tag.BackgroundTransparency = 0.75
                tag.BorderSizePixel = 0
                tag.Text = s.class:sub(1, 5)
                tag.Font = Enum.Font.GothamBold
                tag.TextSize = 7
                tag.TextColor3 = TYPE_COLOR[s.class] or Color3.new(1,1,1)
                tag.Parent = row

                local lbl = Instance.new("TextLabel")
                lbl.Size = UDim2.new(1, -90, 1, 0)
                lbl.Position = UDim2.new(0, 36, 0, 0)
                lbl.BackgroundTransparency = 1
                lbl.Text = s.path
                lbl.Font = Enum.Font.Code
                lbl.TextSize = 8
                lbl.TextColor3 = STATUS_COLOR[s.status] or Color3.fromRGB(200,200,200)
                lbl.TextXAlignment = Enum.TextXAlignment.Left
                lbl.TextTruncate = Enum.TextTruncate.AtEnd
                lbl.Parent = row

                local info = Instance.new("TextLabel")
                info.Size = UDim2.new(0, 50, 1, 0)
                info.Position = UDim2.new(1, -50, 0, 0)
                info.BackgroundTransparency = 1
                info.Text = s.status:sub(1,4) .. "/" ..
                    (s.size >= 1024 and ("%.1fK"):format(s.size/1024) or (s.size .. "B"))
                info.Font = Enum.Font.Code
                info.TextSize = 7
                info.TextColor3 = STATUS_COLOR[s.status] or Color3.fromRGB(180,180,180)
                info.TextXAlignment = Enum.TextXAlignment.Right
                info.Parent = row

                row.MouseButton1Click:Connect(function() copyText(s.path, "path") end)

                batch = batch + 1
                if batch % 50 == 0 then
                    scroll.CanvasSize = UDim2.new(0,0,0, layout.AbsoluteContentSize.Y + 4)
                    task.wait()
                end
            end
        end
        if myToken ~= renderToken then return end
        scroll.CanvasSize = UDim2.new(0,0,0, layout.AbsoluteContentSize.Y + 4)
        status.Text = capped
            and ("Showing %d / %d — FILTER"):format(shown, #allScripts)
            or  ("Shown %d / %d"):format(shown, #allScripts)
    end)
end

-- ==========================================
-- SCAN
-- ==========================================
local function doScan()
    if scanRunning then status.Text = "Scan running..." return end
    scanRunning = true
    scanAbort = false
    renderToken = renderToken + 1
    clearList()
    allScripts = {}
    bigScripts = {}
    status.Text = "Scanning…"
    scanLog("───────────────────────", Color3.fromRGB(80,140,255))
    scanLog("[SCAN] ▶ START (safe mode)", Color3.fromRGB(100,180,255))
    setRtStatus("⏳ starting…", Color3.fromRGB(255, 200, 100))

    task.spawn(function()
        local t0 = os.clock()
        local roots = {}
        for _, name in ipairs({
            "ReplicatedStorage","ReplicatedFirst","StarterPlayer",
            "StarterGui","Workspace","Players","Lighting",
            "SoundService","Chat","Teams"
        }) do
            local ok, svc = pcall(function() return game:GetService(name) end)
            if ok and svc then table.insert(roots, svc) end
        end

        local cRead,cEmpty,cObf,cBc,cTrunc,cSkip = 0,0,0,0,0,0
        local totalSrcBytes = 0
        local rootsSkipped, totalRoots, rootIdx = 0, #roots, 0

        for _, root in ipairs(roots) do
            rootIdx = rootIdx + 1
            if scanAbort then break end
            if not rootEnabled[root.Name] then
                rootsSkipped = rootsSkipped + 1
                scanLog(("[SKIP] %s (disabled)"):format(root.Name),
                    Color3.fromRGB(255, 140, 100))
                task.wait(0.05); continue
            end

            setRtStatus(("⏳ %s | collecting… (%d/%d)")
                :format(root.Name, rootIdx, totalRoots),
                Color3.fromRGB(255, 200, 100))
            task.wait()

            local desc = nil
            local ok = pcall(function() desc = root:GetDescendants() end)
            if not ok or not desc then
                scanLog(("[ERR] %s GetDescendants fail"):format(root.Name),
                    Color3.fromRGB(255, 100, 100))
                continue
            end

            setRtStatus(("⏳ %s | filtering %d inst…")
                :format(root.Name, #desc), Color3.fromRGB(255, 200, 100))
            task.wait()

            local scriptsOnly = {}
            for i = 1, #desc do
                local d = desc[i]
                local c = d.ClassName
                if c == "LocalScript" or c == "ModuleScript" or c == "Script" then
                    if not scanOptions.readCore then
                        local coreName = hasCoreAncestor(d, 5)
                        if coreName then cSkip = cSkip + 1
                        else table.insert(scriptsOnly, d) end
                    else
                        table.insert(scriptsOnly, d)
                    end
                end
                if i % 500 == 0 then task.wait() end
            end
            local totalDesc = #desc
            desc = nil

            local nScripts = #scriptsOnly
            local cappedByLimit = false
            if nScripts > SCAN.MAX_SCRIPTS_ROOT then
                cappedByLimit = true
                local trimmed = {}
                for i = 1, SCAN.MAX_SCRIPTS_ROOT do trimmed[i] = scriptsOnly[i] end
                scriptsOnly = trimmed
                nScripts = SCAN.MAX_SCRIPTS_ROOT
            end

            scanLog(("[ROOT] ▶ %s — %d inst, %d script%s%s")
                :format(root.Name, totalDesc, nScripts,
                    cappedByLimit and " (CAPPED)" or "",
                    cSkip > 0 and (" (+" .. cSkip .. " core skipped)") or ""),
                Color3.fromRGB(150,180,220))

            local rootStart, rootScripts, rootAborted = os.clock(), 0, false

            for i = 1, nScripts do
                if scanAbort then rootAborted = true break end
                if totalSrcBytes > SCAN.MAX_TOTAL_MEM then
                    scanLog("[ABORT] memory limit " ..
                        math.floor(SCAN.MAX_TOTAL_MEM/1024/1024) .. "MB reached",
                        Color3.fromRGB(255, 100, 100))
                    rootAborted = true scanAbort = true break
                end

                local d = scriptsOnly[i]
                local path = d:GetFullName()
                local src, how, origSize = readSource(d, SCAN.MAX_SCRIPT_SIZE)
                local size = origSize or 0
                local st = "empty"

                if src then
                    if how == "truncated" then st = "truncated" cTrunc = cTrunc + 1
                    elseif how == "bcode" then st = "bcode" cBc = cBc + 1
                    else
                        local obfFlag = false
                        if size < 10000 and size > 200 then
                            if src:find("LPH_", 1, true) or src:find("__prometheus", 1, true) then
                                obfFlag = true
                            else
                                local sample = src:sub(1, math.min(#src, 500))
                                local bs = 0
                                for k = 1, #sample do
                                    if sample:byte(k) == 92 then bs = bs + 1 end
                                end
                                if bs > 20 then obfFlag = true end
                            end
                        end
                        if obfFlag then st = "obf" cObf = cObf + 1
                        else st = "readable" cRead = cRead + 1 end
                    end
                    totalSrcBytes = totalSrcBytes + #src

                    if size >= SCAN.BIG_LOG_THRESH then
                        table.insert(bigScripts, {path=path, size=size})
                        scanLog(("[BIG] %.1fKB %s%s"):format(
                            size/1024, path,
                            size > SCAN.MAX_SCRIPT_SIZE and " (TRUNCATED)" or ""),
                            Color3.fromRGB(255, 180, 80))
                    end
                else
                    cEmpty = cEmpty + 1
                end

                rootScripts = rootScripts + 1
                table.insert(allScripts, {
                    inst = d, path = path, class = d.ClassName,
                    size = size, status = st, src = src, how = how,
                })

                local curName = d.Name:sub(1, 12)
                local parName = (d.Parent and d.Parent.Name or "?"):sub(1, 12)
                setRtStatus(("⏳ %s > %s > %s [%d/%d] %.1fKB | r=%d e=%d o=%d t=%d mem=%.1fMB")
                    :format(root.Name, parName, curName, i, nScripts,
                        size/1024, cRead, cEmpty, cObf, cTrunc,
                        totalSrcBytes/1024/1024),
                    Color3.fromRGB(255, 200, 100))
                status.Text = ("Scan… r=%d e=%d o=%d t=%d mem=%.1fMB")
                    :format(cRead, cEmpty, cObf, cTrunc, totalSrcBytes/1024/1024)

                if nScripts > 500 then task.wait()
                elseif nScripts > 200 and i % 2 == 0 then task.wait()
                elseif nScripts > 50 and i % 5 == 0 then task.wait()
                elseif i % 20 == 0 then task.wait() end

                if os.clock() - rootStart > SCAN.ROOT_TIMEOUT then
                    scanLog(("[TIMEOUT] %s >%ds"):format(root.Name, SCAN.ROOT_TIMEOUT),
                        Color3.fromRGB(255, 140, 100))
                    break
                end
            end

            if not rootAborted then
                scanLog(("[ROOT] ✓ %s — %d scripts (%.1fs)")
                    :format(root.Name, rootScripts, os.clock() - rootStart),
                    Color3.fromRGB(100,200,150))
            end
            task.wait()
        end

        local el = os.clock() - t0
        scanLog(("[DONE] r=%d e=%d o=%d bc=%d t=%d skip=%d (%.1fs) mem=%.1fMB")
            :format(cRead,cEmpty,cObf,cBc,cTrunc,cSkip,el,totalSrcBytes/1024/1024),
            Color3.fromRGB(100,255,180))

        if #bigScripts > 0 then
            table.sort(bigScripts, function(a,b) return a.size > b.size end)
            scanLog("[SUMMARY] Top big scripts:", Color3.fromRGB(255, 200, 100))
            for i = 1, math.min(5, #bigScripts) do
                scanLog(("  %d. %.0fKB  %s"):format(
                    i, bigScripts[i].size/1024, bigScripts[i].path),
                    Color3.fromRGB(255, 180, 80))
            end
        end

        if scanAbort then
            scanLog("[DONE] aborted — hasil sebagian", Color3.fromRGB(255, 200, 100))
        end
        status.Text = ("R=%d E=%d O=%d T=%d"):format(cRead, cEmpty, cObf, cTrunc)
        setRtStatus(("✓ done r=%d e=%d o=%d t=%d (%.1fs, %.1fMB)")
            :format(cRead, cEmpty, cObf, cTrunc, el, totalSrcBytes/1024/1024),
            Color3.fromRGB(100,255,180))
        scanRunning = false
        scanAbort = false
        rebuildList()
    end)
end

-- ==========================================
-- SAVE HELPER
-- ==========================================
local function saveToFile(text, prefix)
    local sizeStr = #text >= 1024 and ("%.1f KB"):format(#text/1024) or (#text .. " B")
    if type(writefile) == "function" then
        local fname = prefix .. "_" .. os.date("%Y%m%d_%H%M%S") .. ".txt"
        local ok, err = pcall(writefile, fname, text)
        if ok then
            scanLog("[SAVE] ✓ " .. fname .. " (" .. sizeStr .. ")",
                Color3.fromRGB(100,255,150))
            scanLog("[SAVE] folder: " .. getWorkspacePath(),
                Color3.fromRGB(150,220,255))
            pcall(function() if setclipboard then setclipboard(fname) end end)
            status.Text = "Saved " .. fname
            return true
        else
            scanLog("[SAVE] ✗ writefile: " .. tostring(err),
                Color3.fromRGB(255,100,100))
        end
    end
    local fn = setclipboard or writeclipboard or toclipboard
    if fn then
        local ok2 = pcall(function() fn(text) end)
        if ok2 then
            scanLog("[SAVE] ✓ copied (" .. sizeStr .. ")", Color3.fromRGB(100,255,150))
            status.Text = "Copied (" .. sizeStr .. ")"
            return true
        end
    end
    scanLog("[SAVE] ✗ all failed", Color3.fromRGB(255,100,100))
    return false
end

-- ==========================================
-- BUTTON HANDLERS
-- ==========================================
scanBtn.MouseButton1Click:Connect(doScan)

smartBtn.MouseButton1Click:Connect(function()
    if scanRunning then
        scanLog("[SMART] tunggu scan selesai", Color3.fromRGB(255,180,80)) return
    end
    if #allScripts == 0 then
        scanLog("[SMART] ⚠ belum SCAN — hanya config+runtime", Color3.fromRGB(255,180,80))
    end
    scanLog("[SMART] building pack + snapshot…", Color3.fromRGB(100,220,180))
    local parts = {
        buildConfigSnapshot(),
        buildRuntimeSection(),
        buildMechanics(),
    }
    local text = table.concat(parts, "\n\n")
    scanLog("[SMART] size: " .. (#text >= 1024
        and ("%.1f KB"):format(#text/1024) or (#text .. " B")),
        Color3.fromRGB(100,220,180))
    saveToFile(text, "mechanics")
end)

mechBtn.MouseButton1Click:Connect(function()
    if #allScripts == 0 then
        scanLog("[MECH] scan dulu", Color3.fromRGB(255,180,80)) return
    end
    local text = buildMechanics()
    copyText(text, "mechanics")
    scanLog(("[MECH] %d char copied"):format(#text), Color3.fromRGB(100,200,255))
end)

fullBtn.MouseButton1Click:Connect(function()
    if scanRunning then
        scanLog("[FULL] tunggu scan selesai", Color3.fromRGB(255,180,80)) return
    end
    if #allScripts == 0 then
        scanLog("[FULL] ⚠ belum SCAN — script source kosong", Color3.fromRGB(255,180,80))
    end
    scanLog("[FULL] building full pack…", Color3.fromRGB(180,180,220))
    local parts = {
        buildConfigSnapshot(),
        buildRuntimeSection(),
        buildIndex(),
        buildMechanics(),
        buildRemotes(),
        buildTree(),
        buildConfig(),
    }
    local text = table.concat(parts, "\n\n")
    scanLog("[FULL] size: " .. (#text >= 1024
        and ("%.1f KB"):format(#text/1024) or (#text .. " B")),
        Color3.fromRGB(180,180,220))
    saveToFile(text, "full")
end)

idxBtn.MouseButton1Click:Connect(function()
    if #allScripts == 0 then
        scanLog("[IDX] scan dulu", Color3.fromRGB(255,180,80)) return
    end
    local text = buildIndex()
    copyText(text, ("index (%d)"):format(#allScripts))
    scanLog(("[IDX] %d entries"):format(#allScripts), Color3.fromRGB(150,220,255))
end)

pathBtn.MouseButton1Click:Connect(function()
    if #allScripts == 0 then
        scanLog("[PATH] scan dulu", Color3.fromRGB(255,180,80)) return
    end
    local out = { "=== ALL PATHS ===" }
    local sorted = {}
    for _, s in ipairs(allScripts) do table.insert(sorted, s) end
    table.sort(sorted, function(a,b) return a.path < b.path end)
    for _, s in ipairs(sorted) do
        table.insert(out, ("[%s | %s | %dB] %s")
            :format(s.class, s.status, s.size, s.path))
    end
    copyText(table.concat(out, "\n"), ("paths (%d)"):format(#allScripts))
    scanLog(("[PATH] %d paths"):format(#allScripts), Color3.fromRGB(150,220,255))
end)

remBtn.MouseButton1Click:Connect(function()
    copyText(buildRemotes(), "remotes")
    scanLog("[REM] copied", Color3.fromRGB(150,220,255))
end)

treeBtn.MouseButton1Click:Connect(function()
    copyText(buildTree(), "tree")
    scanLog("[TREE] copied", Color3.fromRGB(150,220,255))
end)

cfgBtn.MouseButton1Click:Connect(function()
    copyText(buildConfig(), "config")
    scanLog("[CFG] copied", Color3.fromRGB(150,220,255))
end)

runBtn.MouseButton1Click:Connect(function()
    if runtimeActive then
        for _, c in ipairs(runtimeConns) do pcall(function() c:Disconnect() end) end
        runtimeConns = {} runtimeActive = false
        runBtn.Text = "RUN"
        runBtn.BackgroundColor3 = Color3.fromRGB(200,120,40)
        scanLog("[RUN] stopped", Color3.fromRGB(200,150,100))
        return
    end
    local ok, conn = pcall(function()
        return game:GetService("LogService").MessageOut:Connect(function(msg, typ)
            local prefix = typ == Enum.MessageType.MessageError and "[ERR] " or
                typ == Enum.MessageType.MessageWarning and "[WRN] " or "[OUT] "
            local line = prefix .. tostring(msg):sub(1,120)
            scanLog(line, typ == Enum.MessageType.MessageError
                and Color3.fromRGB(255,120,120) or Color3.fromRGB(200,200,150))
            table.insert(runtimeCapture.log, {
                time = os.clock(), type = prefix:sub(2,4), msg = tostring(msg):sub(1,120)
            })
            if #runtimeCapture.log > 300 then table.remove(runtimeCapture.log, 1) end
        end)
    end)
    if ok and conn then table.insert(runtimeConns, conn) end
    local hooked = 0
    for _, d in ipairs(game:GetDescendants()) do
        local isRemote = d:IsA("RemoteEvent")
        if not isRemote then
            local okU, res = pcall(function() return d:IsA("UnreliableRemoteEvent") end)
            isRemote = okU and res == true
        end
        if isRemote then
            local ok2, c2 = pcall(function()
                return d.OnClientEvent:Connect(function(...)
                    local args = table.pack(...)
                    local parts = {}
                    for i = 1, math.min(args.n, 5) do
                        local v = args[i]
                        if typeof(v) == "Instance" then
                            parts[i] = v.Name
                        else parts[i] = tostring(v):sub(1, 30) end
                    end
                    scanLog(("← %s(%s)"):format(d.Name, table.concat(parts, ", ")),
                        Color3.fromRGB(100,200,255))
                end)
            end)
            if ok2 and c2 then table.insert(runtimeConns, c2); hooked = hooked + 1 end
        end
    end
    runtimeActive = true
    runBtn.Text = "STOP"
    runBtn.BackgroundColor3 = Color3.fromRGB(180,60,60)
    scanLog(("[RUN] %d remotes hooked + LogService"):format(hooked),
        Color3.fromRGB(100,255,150))
end)

clrBtn.MouseButton1Click:Connect(function()
    if scanRunning then
        scanAbort = true
        scanLog("[CLR] ⏹ abort requested", Color3.fromRGB(255, 180, 100))
        setRtStatus("⏹ aborting…", Color3.fromRGB(255, 140, 100))
        return
    end
    renderToken = renderToken + 1
    clearList()
    allScripts = {} bigScripts = {}
    status.Text = "Cleared."
    scanLog("[CLR] list cleared (runtime tetap)", Color3.fromRGB(200,140,140))
end)

clearLogBtn.MouseButton1Click:Connect(function()
    for _, c in ipairs(logScroll:GetChildren()) do
        if c:IsA("TextLabel") then c:Destroy() end
    end
    logCount = 0
    logScroll.CanvasSize = UDim2.new(0,0,0,0)
end)

filterBox:GetPropertyChangedSignal("Text"):Connect(function()
    filterToken = filterToken + 1
    local t = filterToken
    task.delay(0.3, function()
        if t == filterToken and #allScripts > 0 then rebuildList() end
    end)
end)

scanLog("[BOOT] v13 — Safe Mode + Runtime Capture", Color3.fromRGB(150,180,255))
scanLog("[BOOT] Chip DC/BC/RC OFF = anti-crash", Color3.fromRGB(150,200,255))
scanLog("[BOOT] Chip UI/HK/UC = rekam runtime (bukan scan)", Color3.fromRGB(150,200,255))
scanLog("[BOOT] Tahan chip 0.5 dtk = info (mobile)", Color3.fromRGB(150,200,255))
scanLog("[BOOT] SMART & FULL selalu sertakan config snapshot", Color3.fromRGB(200,180,120))
status.Text = "Ready."
