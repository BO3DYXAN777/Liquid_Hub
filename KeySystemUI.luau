--[[
	Liquid Hub | Key System UI
	- Provider selection (Linkvertise / Work.ink), fetched from backend /api/config
	- Key validation + HWID binding via backend /api/key/check
	- Session saved to file, auto-auth for returning users
	- Discord button (HWID resets are handled in Discord tickets)
	Set BACKEND_URL and DISCORD below after deploying the backend.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local KeySystemUI = {}

--// ========================= CONFIG =========================

local CONFIG = {
	BACKEND_URL = "https://liquid-hub-api.sempaireal.workers.dev", -- live backend
	SCRIPT_NAME = "LiquidHub",
	DISCORD = "https://discord.gg/PdavergNZT", -- HWID resets happen here via tickets
	SESSION_FILE = "LiquidHub/Session.json",
	CACHE_FILE = "LiquidHub/KeyCache.json",
	PROVIDERS = { -- fallback if /api/config is unreachable			{
				Id = "workink",
				Name = "Work.ink",
				Desc = "Official key system - recommended",
				Link = "https://work.ink/1UhX/liquid-hub-key-system",
				Badge = "RECOMMENDED",
				BadgeColor = Color3.fromRGB(96, 220, 148),
			},
			{
				Id = "linkvertise",
				Name = "Linkvertise",
				Desc = "Short checkpoints - same key",
				Link = "https://link-target.net/9180465/c2x4ZHa7kcMj",
				Badge = "",
				BadgeColor = Color3.fromRGB(88, 101, 242),
			},
	},
}

--// ========================= UTILITIES =========================

local function httpGet(url)
	local ok, res = pcall(function()
		if syn and syn.request then
			return syn.request({ Url = url, Method = "GET" }).Body
		elseif http_request then
			return http_request({ Url = url, Method = "GET" }).Body
		elseif request then
			return request({ Url = url, Method = "GET" }).Body
		else
			return game:HttpGet(url, true)
		end
	end)
	if not ok then
		return nil
	end
	return res
end

local function httpGetJson(url)
	local body = httpGet(url)
	if not body then
		return nil
	end
	local ok, decoded = pcall(function()
		return HttpService:JSONDecode(body)
	end)
	if not ok then
		return nil
	end
	return decoded
end

local function clipboardSet(text)
	local done = false
	pcall(function()
		if setclipboard then
			setclipboard(text)
			done = true
		end
	end)
	if not done then
		pcall(function()
			if toclipboard then
				toclipboard(text)
				done = true
			end
		end)
	end
	if not done then
		pcall(function()
			if syn and syn.set_clipboard then
				syn.set_clipboard(text)
			end
		end)
	end
end

local function openUrl(url)
	pcall(function()
		if syn and syn.request then
			syn.request({ Url = url, Method = "GET" })
		end
	end)
end

local function ensureFolder(name)
	if not writefile then
		return
	end
	pcall(function()
		if isfolder and not isfolder(name) then
			makefolder(name)
		end
	end)
end

local function writeJsonFile(path, data)
	if not writefile then
		return
	end
	ensureFolder("LiquidHub")
	pcall(function()
		writefile(path, HttpService:JSONEncode(data))
	end)
end

local function readJsonFile(path)
	local ok, data = pcall(function()
		if isfile and isfile(path) then
			return HttpService:JSONDecode(readfile(path))
		end
		return nil
	end)
	if not ok then
		return nil
	end
	return data
end

local function getHWID()
	local hwid = nil
	pcall(function()
		if gethwid then
			hwid = gethwid()
		end
	end)
	if not hwid then
		hwid = "HWID_" .. Players.LocalPlayer.UserId
	end
	return tostring(hwid)
end

--// ========================= BACKEND API =========================

local remoteDiscord = nil -- set from /api/config if present

local function fetchConfig()
	local cfg = httpGetJson(CONFIG.BACKEND_URL .. "/api/config")
	if cfg and type(cfg.providers) == "table" and #cfg.providers > 0 then
		if type(cfg.discord) == "string" and cfg.discord ~= "" then
			remoteDiscord = cfg.discord
		end
		local list = {}
		for _, p in ipairs(cfg.providers) do
			table.insert(list, {
				Id = p.id,
				Name = p.name,
				Desc = p.desc or "",
				Link = p.link,
				Badge = p.badge or "",
				BadgeColor = Color3.fromRGB(200, 200, 210),
			})
		end
		return list
	end
	return nil
end

local function checkKey(key, hwid)
	local url = CONFIG.BACKEND_URL
		.. "/api/key/check?key="
		.. HttpService:UrlEncode(key)
		.. "&hwid="
		.. HttpService:UrlEncode(hwid)
	return httpGetJson(url)
	-- expected: { ok = true, session = "...", expiresAt = 123 }
	-- failure:  { ok = false, reason = "invalid" | "expired" | "hwid_mismatch" | "banned" }
end

local function verifySession(session, hwid)
	local url = CONFIG.BACKEND_URL
		.. "/api/session/verify?token="
		.. HttpService:UrlEncode(session)
		.. "&hwid="
		.. HttpService:UrlEncode(hwid)
	return httpGetJson(url)
end

--// ========================= UI HELPERS =========================

local function makeCorner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
	return c
end

local function makeStroke(parent, color, thickness)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness or 1
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function toast(parent, text, color)
	local t = Instance.new("TextLabel")
	t.BackgroundColor3 = Color3.fromRGB(24, 24, 30)
	t.TextColor3 = color or Color3.fromRGB(235, 235, 245)
	t.Text = "  " .. text
	t.TextSize = 13
	t.Font = Enum.Font.GothamMedium
	t.Size = UDim2.new(1, -24, 0, 30)
	t.Position = UDim2.new(0, 12, 1, -42)
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.BackgroundTransparency = 0.05
	t.ZIndex = 50
	t.Parent = parent
	makeCorner(t, 8)
	task.delay(2.4, function()
		if t and t.Parent then
			local out = TweenService:Create(t, TweenInfo.new(0.3), {
				TextTransparency = 1,
				BackgroundTransparency = 1,
			})
			out:Play()
			out.Completed:Wait()
			t:Destroy()
		end
	end)
end

--// ========================= MAIN =========================

function KeySystemUI.Run(onSuccess)
	task.spawn(function()
		local hwid = getHWID()

		-- 1) Try cached session (returning user, no UI needed)
		local cache = readJsonFile(CONFIG.CACHE_FILE)
		if cache and cache.session and cache.hwid == hwid then
			local v = verifySession(cache.session, hwid)
			if v and v.ok then
				onSuccess(cache.session)
				return
			end
		end

		-- 2) Build the UI
		local player = Players.LocalPlayer

		local gui = Instance.new("ScreenGui")
		gui.Name = "LiquidHub_KeySystem"
		gui.ResetOnSpawn = false
		gui.IgnoreGuiInset = true
		gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		gui.DisplayOrder = 999
		local parented = false
		pcall(function()
			if gethui then
				gui.Parent = gethui()
				parented = true
			end
		end)
		if not parented then
			gui.Parent = player:WaitForChild("PlayerGui")
		end

		-- dim + blur backdrop
		local blur = Instance.new("BlurEffect")
		blur.Size = 0
		blur.Parent = game:GetService("Workspace").CurrentCamera
		TweenService:Create(blur, TweenInfo.new(0.4), { Size = 12 }):Play()

		local dim = Instance.new("Frame")
		dim.BackgroundColor3 = Color3.fromRGB(8, 8, 12)
		dim.Size = UDim2.fromScale(1, 1)
		dim.BackgroundTransparency = 1
		dim.Parent = gui
		TweenService:Create(dim, TweenInfo.new(0.4), { BackgroundTransparency = 0.25 }):Play()

		-- card
		local card = Instance.new("Frame")
		card.Size = UDim2.fromOffset(430, 540)
		card.Position = UDim2.fromScale(0.5, 0.5)
		card.AnchorPoint = Vector2.new(0.5, 0.5)
		card.BackgroundColor3 = Color3.fromRGB(17, 17, 23)
		card.BorderSizePixel = 0
		card.Parent = gui
		makeCorner(card, 14)
		makeStroke(card, Color3.fromRGB(52, 52, 66), 1)

		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Vertical
		layout.Padding = UDim.new(0, 10)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layout.Parent = card

		local pad = Instance.new("UIPadding")
		pad.PaddingTop = UDim.new(0, 22)
		pad.PaddingBottom = UDim.new(0, 18)
		pad.PaddingLeft = UDim.new(0, 22)
		pad.PaddingRight = UDim.new(0, 22)
		pad.Parent = card

		-- header
		local header = Instance.new("Frame")
		header.Size = UDim2.new(1, 0, 0, 52)
		header.BackgroundTransparency = 1
		header.LayoutOrder = 1
		header.Parent = card

		local logo = Instance.new("TextLabel")
		logo.Size = UDim2.new(1, 0, 0, 28)
		logo.BackgroundTransparency = 1
		logo.Text = "LIQUID HUB"
		logo.Font = Enum.Font.GothamBlack
		logo.TextColor3 = Color3.fromRGB(255, 255, 255)
		logo.TextSize = 24
		logo.Parent = header

		local sub = Instance.new("TextLabel")
		sub.Size = UDim2.new(1, 0, 0, 14)
		sub.Position = UDim2.new(0, 0, 0, 32)
		sub.BackgroundTransparency = 1
		sub.Text = "KEY SYSTEM"
		sub.Font = Enum.Font.GothamBold
		sub.TextColor3 = Color3.fromRGB(96, 220, 148)
		sub.TextSize = 12
		sub.TextTransparency = 0.2
		sub.Parent = header

		-- status line
		local status = Instance.new("TextLabel")
		status.Size = UDim2.new(1, 0, 0, 18)
		status.BackgroundTransparency = 1
		status.LayoutOrder = 2
		status.Font = Enum.Font.GothamMedium
		status.TextColor3 = Color3.fromRGB(160, 160, 175)
		status.TextSize = 13
		status.Text = "Select a service to get your key"
		status.Parent = card

		-- provider cards container
		local providersFrame = Instance.new("Frame")
		providersFrame.Size = UDim2.new(1, 0, 0, 0)
		providersFrame.AutomaticSize = Enum.AutomaticSize.Y
		providersFrame.BackgroundTransparency = 1
		providersFrame.LayoutOrder = 3
		providersFrame.Parent = card

		local pList = Instance.new("UIListLayout")
		pList.Padding = UDim.new(0, 8)
		pList.SortOrder = Enum.SortOrder.LayoutOrder
		pList.Parent = providersFrame

		local function addProvider(p, order)
			local btn = Instance.new("TextButton")
			btn.Size = UDim2.new(1, 0, 0, 62)
			btn.BackgroundColor3 = Color3.fromRGB(24, 24, 31)
			btn.AutoButtonColor = false
			btn.Text = ""
			btn.BorderSizePixel = 0
			btn.LayoutOrder = order
			btn.Parent = providersFrame
			makeCorner(btn, 10)
			makeStroke(btn, Color3.fromRGB(45, 45, 56), 1)

			local name = Instance.new("TextLabel")
			name.Size = UDim2.new(1, -110, 0, 20)
			name.Position = UDim2.new(0, 14, 0, 12)
			name.BackgroundTransparency = 1
			name.Font = Enum.Font.GothamBold
			name.TextSize = 15
			name.TextXAlignment = Enum.TextXAlignment.Left
			name.TextColor3 = Color3.fromRGB(235, 235, 245)
			name.Text = p.Name
			name.Parent = btn

			local desc = Instance.new("TextLabel")
			desc.Size = UDim2.new(1, -110, 0, 16)
			desc.Position = UDim2.new(0, 14, 0, 34)
			desc.BackgroundTransparency = 1
			desc.Font = Enum.Font.Gotham
			desc.TextSize = 12
			desc.TextXAlignment = Enum.TextXAlignment.Left
			desc.TextColor3 = Color3.fromRGB(140, 140, 155)
			desc.Text = p.Desc
			desc.Parent = btn

			local badge = Instance.new("TextLabel")
			badge.Size = UDim2.new(0, 90, 0, 20)
			badge.Position = UDim2.new(1, -106, 0, 12)
			badge.BackgroundTransparency = 1
			badge.Font = Enum.Font.GothamBold
			badge.TextSize = 10
			badge.TextXAlignment = Enum.TextXAlignment.Right
			badge.TextColor3 = p.BadgeColor or Color3.fromRGB(200, 200, 210)
			badge.Text = p.Badge
			badge.Parent = btn

			-- Linkvertise links carry the HWID so the backend claim page binds the key to this device
		local link = p.Link
		if p.Id == "linkvertise" then
			link = link .. (string.find(link, "?", 1, true) and "&" or "?")
				.. "hwid=" .. HttpService:UrlEncode(getHWID())
		end

		local copyIcon = Instance.new("TextButton")
			copyIcon.Size = UDim2.new(0, 28, 0, 28)
			copyIcon.Position = UDim2.new(1, -40, 0, 17)
			copyIcon.BackgroundColor3 = Color3.fromRGB(35, 35, 44)
			copyIcon.Text = "CP"
			copyIcon.Font = Enum.Font.GothamBold
			copyIcon.TextSize = 10
			copyIcon.TextColor3 = Color3.fromRGB(200, 200, 210)
			copyIcon.AutoButtonColor = false
			copyIcon.BorderSizePixel = 0
			copyIcon.Parent = btn
			makeCorner(copyIcon, 7)

			copyIcon.MouseEnter:Connect(function()
				TweenService:Create(copyIcon, TweenInfo.new(0.15), { BackgroundColor3 = Color3.fromRGB(48, 48, 60) }):Play()
			end)
			copyIcon.MouseLeave:Connect(function()
				TweenService:Create(copyIcon, TweenInfo.new(0.15), { BackgroundColor3 = Color3.fromRGB(35, 35, 44) }):Play()
			end)
			copyIcon.MouseButton1Click:Connect(function()
				clipboardSet(link)
				toast(card, "Link copied to clipboard!", Color3.fromRGB(96, 220, 148))
			end)

			-- whole row: copy + attempt to open
			btn.MouseButton1Click:Connect(function()
				clipboardSet(link)
				openUrl(link)
				toast(card, p.Name .. " link copied - open it in your browser", Color3.fromRGB(96, 220, 148))
				status.Text = "Complete the steps on " .. p.Name .. ", then paste your key below."
				status.TextColor3 = Color3.fromRGB(160, 160, 175)
			end)
			btn.MouseEnter:Connect(function()
				TweenService:Create(btn, TweenInfo.new(0.15), { BackgroundColor3 = Color3.fromRGB(30, 30, 38) }):Play()
			end)
			btn.MouseLeave:Connect(function()
				TweenService:Create(btn, TweenInfo.new(0.15), { BackgroundColor3 = Color3.fromRGB(24, 24, 31) }):Play()
			end)
		end

		local providers = fetchConfig() or CONFIG.PROVIDERS
		for i, p in ipairs(providers) do
			addProvider(p, i)
		end

		-- key input
		local inputBg = Instance.new("Frame")
		inputBg.Size = UDim2.new(1, 0, 0, 44)
		inputBg.BackgroundColor3 = Color3.fromRGB(24, 24, 31)
		inputBg.BorderSizePixel = 0
		inputBg.LayoutOrder = 4
		inputBg.Parent = card
		makeCorner(inputBg, 10)
		local inStroke = makeStroke(inputBg, Color3.fromRGB(45, 45, 56), 1)

		local input = Instance.new("TextBox")
		input.Size = UDim2.new(1, -20, 1, -10)
		input.Position = UDim2.new(0, 10, 0, 5)
		input.BackgroundTransparency = 1
		input.Font = Enum.Font.GothamMedium
		input.TextSize = 13
		input.TextColor3 = Color3.fromRGB(235, 235, 245)
		input.PlaceholderText = "Enter / paste your key here"
		input.PlaceholderColor3 = Color3.fromRGB(110, 110, 125)
		input.Text = ""
		input.ClearTextOnFocus = false
		input.TextXAlignment = Enum.TextXAlignment.Left
		input.Parent = inputBg

		-- buttons row: Check Key + Discord
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 42)
		row.BackgroundTransparency = 1
		row.LayoutOrder = 5
		row.Parent = card

		local rowLayout = Instance.new("UIListLayout")
		rowLayout.FillDirection = Enum.FillDirection.Horizontal
		rowLayout.Padding = UDim.new(0, 10)
		rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
		rowLayout.Parent = row

		local function makeButton(text, color, order)
			local b = Instance.new("TextButton")
			b.Size = UDim2.new(0.5, -5, 1, 0)
			b.BackgroundColor3 = color
			b.Font = Enum.Font.GothamBold
			b.TextSize = 13
			b.TextColor3 = Color3.fromRGB(255, 255, 255)
			b.Text = text
			b.AutoButtonColor = false
			b.BorderSizePixel = 0
			b.LayoutOrder = order
			b.Parent = row
			makeCorner(b, 10)
			return b
		end

		local checkBtn = makeButton("Check Key", Color3.fromRGB(96, 220, 148), 1)
		local discordBtn = makeButton("Discord", Color3.fromRGB(88, 101, 242), 2)

		-- HWID hint line
		local hint = Instance.new("TextLabel")
		hint.Size = UDim2.new(1, 0, 0, 16)
		hint.BackgroundTransparency = 1
		hint.LayoutOrder = 6
		hint.Font = Enum.Font.Gotham
		hint.TextSize = 11
		hint.TextColor3 = Color3.fromRGB(130, 130, 145)
		hint.Text = "Changed PC? HWID reset in our Discord - open a ticket"
		hint.Parent = card

		-- footer
		local footer = Instance.new("TextLabel")
		footer.Size = UDim2.new(1, 0, 0, 14)
		footer.BackgroundTransparency = 1
		footer.LayoutOrder = 7
		footer.Font = Enum.Font.Gotham
		footer.TextSize = 11
		footer.TextColor3 = Color3.fromRGB(120, 120, 135)
		footer.Text = CONFIG.SCRIPT_NAME .. " v" .. (getgenv().LH_VERSION or "1.0.0")
		footer.Parent = card

		--// ==================== ACTIONS ====================

		local function setStatus(text, color)
			status.Text = text
			status.TextColor3 = color or Color3.fromRGB(160, 160, 175)
		end

		local function teardown(onDone)
			TweenService:Create(blur, TweenInfo.new(0.35), { Size = 0 }):Play()
			TweenService:Create(dim, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
			task.delay(0.35, function()
				pcall(function()
					gui:Destroy()
				end)
				pcall(function()
					blur:Destroy()
				end)
				onDone()
			end)
		end

		local checking = false
		local function doCheck()
			if checking then
				return
			end
			local key = string.gsub(input.Text, "%s+", "")
			if key == "" then
				setStatus("Enter a key first.", Color3.fromRGB(255, 170, 90))
				return
			end
			checking = true
			checkBtn.Text = "Checking..."
			setStatus("Verifying key with server...")
			task.spawn(function()
				local res = checkKey(key, hwid)
				if res and res.ok and res.session then
					writeJsonFile(CONFIG.CACHE_FILE, { key = key, hwid = hwid, session = res.session })
					writeJsonFile(CONFIG.SESSION_FILE, { session = res.session, hwid = hwid })
					setStatus("Key valid! Loading Liquid Hub...", Color3.fromRGB(96, 220, 148))
					task.wait(0.8)
					teardown(function()
						onSuccess(res.session)
					end)
				elseif res and res.ok and res.existingKey then
					-- this device already owns a live free key; new keys can't be earned until it expires
					local left = res.expiresAt and (res.expiresAt - os.time() * 1000) or 0
					local mins = math.max(1, math.ceil(left / 60000))
					local when
					if mins >= 60 then
						when = string.format("%dh %02dm", math.floor(mins / 60), mins % 60)
					else
						when = mins .. "m"
					end
					setStatus("You already have a key! Time left: " .. when .. ". New keys unlock when it expires.", Color3.fromRGB(255, 200, 90))
				elseif res and res.reason == "hwid_mismatch" then
					setStatus("Key is bound to another device. HWID reset in Discord.", Color3.fromRGB(255, 130, 90))
				elseif res and res.reason == "expired" then
					setStatus("Key expired - get a new one.", Color3.fromRGB(255, 130, 90))
				elseif res and res.reason == "rate_limited" then
					setStatus("Too many attempts - wait a minute and try again.", Color3.fromRGB(255, 170, 90))
				elseif res and res.reason == "banned" then
					setStatus("This key is banned. Appeal in Discord.", Color3.fromRGB(255, 130, 90))
				else
					setStatus("Invalid key or server unreachable. Try again.", Color3.fromRGB(255, 130, 90))
				end
				checking = false
				checkBtn.Text = "Check Key"
			end)
		end

		checkBtn.MouseButton1Click:Connect(doCheck)
		input.FocusLost:Connect(function(enterPressed)
			if enterPressed then
				doCheck()
			end
		end)

		discordBtn.MouseButton1Click:Connect(function()
			clipboardSet(remoteDiscord or CONFIG.DISCORD)
			toast(card, "Discord invite copied - HWID resets via ticket there.", Color3.fromRGB(88, 101, 242))
		end)

		-- draggable card
		do
			local dragging = false
			local dragStart = nil
			local startPos = nil
			card.InputBegan:Connect(function(io)
				if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch then
					dragging = true
					dragStart = io.Position
					startPos = card.Position
				end
			end)
			UserInputService.InputChanged:Connect(function(io)
				if dragging and (io.UserInputType == Enum.UserInputType.MouseMovement or io.UserInputType == Enum.UserInputType.Touch) then
					local delta = io.Position - dragStart
					card.Position = UDim2.new(
						startPos.X.Scale,
						startPos.X.Offset + delta.X,
						startPos.Y.Scale,
						startPos.Y.Offset + delta.Y
					)
				end
			end)
			UserInputService.InputEnded:Connect(function(io)
				if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch then
					dragging = false
				end
			end)
		end

		-- entrance animation
		card.Visible = false
		card.Position = UDim2.new(0.5, 0, 0.56, 0)
		task.delay(0.05, function()
			card.Visible = true
			TweenService:Create(card, TweenInfo.new(0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
				Position = UDim2.new(0.5, 0, 0.5, 0),
			}):Play()
		end)

		-- focus the input on desktop for fast paste
		task.delay(0.6, function()
			pcall(function()
				input:CaptureFocus()
			end)
		end)
	end)
end

return KeySystemUI
