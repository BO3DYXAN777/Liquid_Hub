-- Universal Hub Loader | supports multiple games | Delta Plugin fix included
-- Key system gate: provider selection (Work.ink / Linkvertise) + HWID binding + session cache
-- Supported: Final Swarm, Chess Incremental, Sticks Incremental 2

local KEY_SYSTEM_URL = "https://raw.githubusercontent.com/BO3DYXAN777/Liquid_Hub/refs/heads/main/KeySystemUI.luau"
local LOCAL_KEY_UI = "LiquidHub/KeySystemUI.luau" -- optional local cache on disk (auto-written after first successful load)

local REPO = "https://raw.githubusercontent.com/BO3DYXAN777/Liquid_Hub/refs/heads/main/"

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
		warn("[Universal Loader] Game not supported: PlaceId=" .. tostring(pid) .. " GameId=" .. tostring(gid) .. " Name=" .. tostring(game.Name))
		pcall(function()
			game:GetService("StarterGui"):SetCore("SendNotification", {
				Title = "Universal Loader",
				Text = "Game not supported: " .. tostring(pid),
				Duration = 5,
			})
		end)
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
		KeySystemUI.Run(startHub)
	else
		-- FAIL CLOSED: no key UI = no hub. Never bypass the key system.
		warn("[Universal Loader] Key system unavailable - hub stays locked. Check your internet or try again.")
		pcall(function()
			game:GetService("StarterGui"):SetCore("SendNotification", {
				Title = "Liquid Hub",
				Text = "Key system failed to load - re-inject and try again.",
				Duration = 6,
			})
		end)
	end
end)
