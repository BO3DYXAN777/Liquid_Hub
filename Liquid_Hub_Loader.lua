-- Universal Hub Loader | supports multiple games | Delta Plugin fix included
-- Key system gate: provider selection (Work.ink / Linkvertise) + HWID binding + session cache
-- Supported: Final Swarm, Chess Incremental, Sticks Incremental 2

local KEY_SYSTEM_URL = "https://raw.githubusercontent.com/BO3DYXAN777/Liquid_Hub/refs/heads/main/KeySystemUI.luau"
local LOCAL_KEY_UI = "LiquidHub/KeySystemUI.luau" -- optional local cache on disk (auto-written after first successful load)

local REPO = "https://raw.githubusercontent.com/BO3DYXAN777/Liquid_Hub/refs/heads/main/"

-- Always-visible on-screen status card. "Nothing appears" is no longer possible:
-- any failure (unsupported game, load error, key system down) shows up on screen.
local function showFatal(title, text)
	pcall(function()
		local gui = Instance.new("ScreenGui")
		gui.Name = "LiquidHub_LoaderStatus"
		gui.ResetOnSpawn = false
		gui.DisplayOrder = 1000
		local parented = false
		pcall(function()
			if gethui then
				gui.Parent = gethui()
				parented = true
			end
		end)
		if not parented then
			gui.Parent = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
		end
		local card = Instance.new("Frame")
		card.AnchorPoint = Vector2.new(0.5, 1)
		card.Position = UDim2.new(0.5, 0, 1, -40)
		card.Size = UDim2.fromOffset(400, 88)
		card.BackgroundColor3 = Color3.fromRGB(17, 17, 23)
		card.BorderSizePixel = 0
		card.Parent = gui
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 10)
		corner.Parent = card
		local t1 = Instance.new("TextLabel")
		t1.Size = UDim2.new(1, -20, 0, 24)
		t1.Position = UDim2.new(0, 10, 0, 8)
		t1.BackgroundTransparency = 1
		t1.Font = Enum.Font.GothamBold
		t1.TextSize = 15
		t1.TextColor3 = Color3.fromRGB(255, 130, 90)
		t1.Text = title
		t1.Parent = card
		local t2 = Instance.new("TextLabel")
		t2.Size = UDim2.new(1, -20, 1, -40)
		t2.Position = UDim2.new(0, 10, 0, 34)
		t2.BackgroundTransparency = 1
		t2.Font = Enum.Font.Gotham
		t2.TextSize = 12
		t2.TextWrapped = true
		t2.TextColor3 = Color3.fromRGB(210, 210, 220)
		t2.Text = text
		t2.Parent = card
		task.delay(12, function()
			pcall(function()
				gui:Destroy()
			end)
		end)
	end)
	warn("[Liquid Hub] " .. title .. ": " .. text)
end

local SUPPORTED = {
	-- Final Swarm
	[99521272836282] = REPO .. "Final%20Swarm.luau", -- Final Swarm main
	[797875825749] = REPO .. "Final%20Swarm.luau", -- Final Swarm Raid
	[9551044479] = REPO .. "Final%20Swarm.luau", -- Final Swarm Universe

	-- Chess Incremental
	[72119929635167] = REPO .. "ChessInc_.luau", -- Chess Incremental Place
	[10381920426] = REPO .. "ChessInc_.luau", -- Chess Incremental Game

	-- Sticks Incremental 2: TODO paste the real PlaceId(s) from the game URL (roblox.com/games/<PLACEID>/...)
	-- [0000000000] = REPO .. "Sticks%20Inc%202_.luau", -- Sticks Incremental 2
	-- [0000000000] = REPO .. "Sticks%20Inc%202_.luau", -- Sticks Incremental 2 (alt place)
	-- [0000000000] = REPO .. "Sticks%20Inc%202_.luau", -- Sticks Incremental 2 (universe id)
}

local STICKS_URL = REPO .. "Sticks%20Inc%202_.luau" -- matched by game name until real PlaceIds are added above

local function withPlugin(fn)
	local get = getthreadidentity or get_thread_identity or function() return 8 end
	local set = setthreadidentity or set_thread_identity or setthreadcontext or set_identity
	local old = get and get() or 8
	if set then pcall(set, 8) end
	local ok, res = pcall(fn)
	if set then pcall(set, old) end
	if not ok then error(res) end
	return res
end

withPlugin(function()
	local pid = game.PlaceId
	local gid = game.GameId
	local url = SUPPORTED[pid] or SUPPORTED[gid]

	-- fallback by name / map detection (for Final Swarm if place changes / Raid sub-place)
	if not url then
		local name = game.Name:lower()

		if name:find("swarm") then
			url = SUPPORTED[99521272836282]
		elseif name:find("sticks incremental") or name:find("sticks") then
			url = STICKS_URL
		elseif workspace:FindFirstChild("Enemies") then
			local ok, hasRaid = pcall(function()
				for _, e in ipairs(workspace.Enemies:GetChildren()) do
					if e.Name:lower():find("raid") or e.Name:lower():find("tomb") then
						return true
					end
				end
				return false
			end)
			if ok and hasRaid then
				url = SUPPORTED[99521272836282]
			end
		end

		if not url and workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Floor") then
			local ok, hasFloor = pcall(function()
				return workspace.Map.Floor.Size.Magnitude > 1000
			end)
			if ok and hasFloor then
				url = SUPPORTED[99521272836282]
			end
		end
	end

	if not url then
		showFatal(
			"Game not supported",
			"PlaceId=" .. tostring(pid) .. " | GameId=" .. tostring(gid) .. " | Name=" .. tostring(game.Name) .. " - send this to the developer"
		)
		return
	end

	--// ================= KEY SYSTEM GATE =================
	-- Key UI loads REMOTE-FIRST so updates go live instantly; local cache is only an offline fallback.

	local function loadKeySystemUI()
		-- 1) GitHub (always fresh)
		local source = nil
		local okRemote, remote = pcall(function()
			source = game:HttpGet(KEY_SYSTEM_URL, true)
			return loadstring(source)()
		end)
		if okRemote and remote then
			-- cache for offline fallback
			pcall(function()
				if writefile then
					if isfolder and not isfolder("LiquidHub") then
						makefolder("LiquidHub")
					end
					writefile(LOCAL_KEY_UI, source)
				end
			end)
			return remote
		end

		-- 2) Local cache (only if GitHub is unreachable)
		local okLocal, localMod = pcall(function()
			if readfile and isfile and isfile(LOCAL_KEY_UI) then
				local fn = loadstring(readfile(LOCAL_KEY_UI))
				if fn then
					return fn()
				end
			end
			error("no local copy")
		end)
		if okLocal and localMod then
			return localMod
		end

		warn("[Universal Loader] Key system UI failed to load: " .. tostring(remote))
		showFatal(
			"Key system failed to load",
			"Check your internet and re-inject. If it keeps failing, tell the developer: " .. tostring(remote)
		)
		return nil
	end

	local KeySystemUI = loadKeySystemUI()

	local function startHub(sessionToken)
		getgenv().LiquidHubSession = sessionToken
		local ok, err = pcall(function()
			loadstring(game:HttpGet(url, true))()
		end)
		if not ok then
			warn("[Universal Loader] Failed to load hub: " .. tostring(err))
		end
	end

	if KeySystemUI and KeySystemUI.Run then
		local ok, err = pcall(KeySystemUI.Run, startHub)
		if not ok then
			showFatal("Key system error", tostring(err))
		end
	else
		-- FAIL CLOSED: no key UI = no hub. Never bypass the key system.
		showFatal("Key system unavailable", "The key UI could not be loaded - hub stays locked. Re-inject and try again.")
	end
end)
