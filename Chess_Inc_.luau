-- Chess_Inc_NewUi | Chess Incremental | Liquid Hub (Nebula UI)
-- Ported from "ChessInc.luau" (WindUI) onto the new Liquid Hub UI lib.
-- All feature logic (farm, upgrades, codes, teleports, configs) is preserved
-- 1:1; only the UI adapter layer changed. Folder: ChessInc | Flags: CHS_
-- Plus: Anti-AFK (VirtualUser idleness, same as Sticks_Inc2_).

-- AUTO Plugin fix for Delta / WindUI (1 loadstring, no external wrapper needed)
pcall(function()
	local set = setthreadidentity or set_thread_identity or setthreadcontext or _G.set_identity
	if set then pcall(set, 8) pcall(set, 7) end
end)

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

local function getFlag(n) return RS:GetAttribute("CHS_" .. n) end
local function setFlag(n, v) RS:SetAttribute("CHS_" .. n, v) end

-- Every load stamps a unique generation into the DataModel. Loops check it, so
-- a loop left running by an EARLIER execution of this script stops as soon as
-- a new copy loads (prevents duplicate loops fighting over the same remotes).
local LOAD_GEN = math.floor(os.clock() * 100000) % 1000000 + math.random(1, 999) * 1000000
RS:SetAttribute("CHS_LoadGen", LOAD_GEN)
local function isCurrentGen() return RS:GetAttribute("CHS_LoadGen") == LOAD_GEN end

-- ===================== LIQUID HUB CORE (live-reload contract) =====================
local STATE = _G.STATE
if typeof(STATE) ~= "table" then STATE = {} end
STATE.GEN = math.floor(os.clock() * 100000)
RS:SetAttribute("CHS_LiquidGen", STATE.GEN)
local __cleanups = {}
if type(STATE.onCleanup) ~= "function" then
	function STATE.onCleanup(fn)
		if type(fn) == "function" then table.insert(__cleanups, fn) end
	end
end
if type(STATE.connect) ~= "function" then
	function STATE.connect(signal, fn)
		return signal:Connect(fn)
	end
end
if type(STATE.alive) ~= "function" then
	function STATE.alive()
		return RS:GetAttribute("CHS_LiquidGen") == STATE.GEN and isCurrentGen()
	end
end

-- Interval-driven loop runner: pcall-protected, alive-checked.
local function loop(name, interval, fn)
	task.spawn(function()
		while STATE.alive() do
			local ok, err = pcall(fn)
			if not ok then
				warn("[LiquidHub/" .. name .. "] " .. tostring(err))
			end
			local t = 0
			while t < interval and STATE.alive() do
				local dt = task.wait(0.1)
				t = t + (dt or 0.1)
			end
		end
	end)
end

-- ===================== GAME REMOTES =====================
local Remotes = RS:WaitForChild("Remotes", 10)
if not Remotes then
	warn("[LiquidHub] Remotes not found")
	return
end

local UpgradePurchase = Remotes:FindFirstChild("UpgradePurchase")
local ShopRedeemCode = Remotes:FindFirstChild("ShopRedeemCode")
local FragmentsClick = Remotes:FindFirstChild("FragmentsClick")
local RubinsExchangeRequest = Remotes:FindFirstChild("RubinsExchangeRequest")
local PrestigeRequest = Remotes:FindFirstChild("PrestigeRequest")
local Collect = Remotes:FindFirstChild("Collect")

-- Destroy any previous hub window (Nebula/WindUI/Rayfield create a fresh
-- ScreenGui each time). Without this every reload stacks another window.
pcall(function()
	local rg = game.CoreGui:FindFirstChild("RobloxGui")
	local parents = { game.CoreGui }
	if rg then parents[#parents + 1] = rg end
	pcall(function()
		local pg = LocalPlayer:FindFirstChild("PlayerGui")
		if pg then parents[#parents + 1] = pg end
	end)
	for _, parent in ipairs(parents) do
		for _, sg in ipairs(parent:GetChildren()) do
			if sg:IsA("ScreenGui") and sg ~= rg then
				local hit = false
				for _, c in ipairs(sg:GetDescendants()) do
					if (c:IsA("TextLabel") or c:IsA("TextButton"))
						and (c.Text == "Liquid Hub" or c.Text == "Chess Incremental" or c.Text == "Sticks Inc 2" or c.Text == "UI Template") then
						hit = true
						break
					end
				end
				if hit then sg:Destroy() end
			end
		end
	end
end)

-- ===================== LIBRARY LOAD (Nebula / Liquid Hub) =====================
local LIB_SOURCES = {
	"https://raw.githubusercontent.com/tyanxblack2-max/asdfasd/refs/heads/main/Source.lua",
	"https://cdn.jsdelivr.net/gh/tyanxblack2-max/asdfasd@main/Source.lua",
}
local Liquid = nil
for _, url in ipairs(LIB_SOURCES) do
	local ok, res = pcall(function()
		return game:HttpGet(url .. "?nocache=" .. tostring(os.time()))
	end)
	if ok and type(res) == "string" and #res > 2000 then
		local chunk, cerr = (loadstring or load)(res)
		if chunk then
			local okLib, lib = pcall(chunk)
			if okLib and type(lib) == "table" then
				Liquid = lib
				break
			end
		else
			warn("[ChessInc] Compile error: " .. tostring(cerr))
		end
	end
end
if not Liquid then
	warn("[ChessInc] Failed to load Liquid Hub library from all sources")
	return
end

-- ===================== GAME DETECTION (for the title bar) =====================
local GAME_NAME = "Chess Incremental"
do
	local pid = game.PlaceId
	local ok, name = pcall(function()
		local Http = game:GetService("HttpService")
		local res = game:HttpGet("https://apis.roblox.com/universes/v1/places/" .. pid .. "/universe")
		local universeId = Http:JSONDecode(res).universeId
		local res2 = game:HttpGet("https://games.roblox.com/v1/games?universeIds=" .. universeId)
		return Http:JSONDecode(res2).data[1].name
	end)
	if ok and type(name) == "string" and #name > 0 then
		GAME_NAME = name
	end
end

local WindowRaw = Liquid:CreateWindow({
	Title     = "Liquid Hub",
	SubTitle  = "1.0.0",
	GameName  = GAME_NAME,
	ToggleKey = Enum.KeyCode.RightShift,
	Width     = 680,
	Height    = 440,
})

-- ===================== OLD-SCRIPT -> NEBULA ADAPTER =====================
-- The ChessInc feature code below still calls tab:CreateToggle / CreateSlider /
-- CreateDropdown / CreateButton / window:Notify in the old table format; these
-- shims translate them to Nebula. Logic untouched.

-- Config registry: adapter records every Toggle/Slider/Dropdown (name -> element
-- + last value + applier) so the Configs tab can save/apply whole setups.
-- Elements with noreg = true (meta UI) are skipped.
local Reg = {}

-- elements can be called the OLD positional way ("Name", callback) or with a
-- table ({name=..., callback=...}); normalize both to a table
local function normOpts(o, cb)
	if type(o) == "string" then return { name = o, callback = cb } end
	return o or {}
end

local function adaptSection(sect)
	local s = {}

	function s:CreateLabel(o)
		return sect:CreateLabel(type(o) == "table" and (o.name or o.Title or "") or o)
	end

	function s:CreateToggle(o)
		o = normOpts(o)
		local entry = { kind = "toggle", current = o.value and true or false }
		local function wrappedCb(v)
			entry.current = v
			if o.callback then return o.callback(v) end
		end
		local obj = sect:CreateToggle(o.name, o.value and true or false, wrappedCb, o.name)
		entry.obj = obj
		entry.apply = function(v)
			if type(v) ~= "boolean" then return end
			pcall(function() obj.Set(v) end)
			pcall(function() wrappedCb(v) end)
		end
		if o.name and not o.noreg then Reg[o.name] = entry end
		return obj
	end

	function s:CreateSlider(o)
		o = normOpts(o)
		local mn, mx = 0, 100
		if type(o.range) == "table" then
			mn = o.range[1] or 0
			mx = o.range[2] or 100
		end
		local entry = { kind = "slider", current = o.value }
		local function wrappedCb(v)
			entry.current = v
			if o.callback then return o.callback(v) end
		end
		local obj = sect:CreateSlider(o.name, mn, mx, o.value, wrappedCb, o.name)
		entry.obj = obj
		entry.apply = function(v)
			if type(v) ~= "number" then return end
			pcall(function() obj.Set(v) end)
			pcall(function() wrappedCb(v) end)
		end
		if o.name and not o.noreg then Reg[o.name] = entry end
		return obj
	end

	function s:CreateDropdown(o)
		o = normOpts(o)
		local initVal = o.value
		local entry = { kind = "dropdown", multi = o.multiSelect or false }
		local function wrappedCb(v)
			entry.current = v
			if o.callback then return o.callback(v) end
		end
		local obj
		if o.multiSelect then
			obj = sect:CreateMultiDropdown(o.name, o.options or {}, type(initVal) == "table" and initVal or {}, wrappedCb, o.name)
		elseif type(o.options) == "table" and #o.options > 20 then
			obj = sect:CreateSearchDropdown(o.name, o.options or {}, initVal, wrappedCb, o.name)
		else
			obj = sect:CreateDropdown(o.name, o.options or {}, initVal, wrappedCb, o.name)
		end
		entry.obj = obj
		entry.apply = function(v)
			if type(v) ~= "string" and type(v) ~= "table" then return end
			pcall(function() obj.Set(v) end)
			pcall(function() wrappedCb(v) end)
		end
		if o.name and not o.noreg then Reg[o.name] = entry end
		return obj
	end

	function s:CreateButton(o, cb)
		o = normOpts(o, cb)
		return sect:CreateButton(o.name, o.callback)
	end

	function s:CreateInput(o)
		o = normOpts(o)
		return sect:CreateTextbox(o.name, o.placeholder, o.callback, o.name)
	end

	return s
end

local function adaptTab(wtab)
	local t = {}
	t._raw = wtab
	t._cur = nil -- current section: tab-level element calls land here

	function t:CreateSection(o)
		local nm = o and (o.name or o.Title) or ""
		local col = o and o.column or nil -- nil = lib auto-balances across columns
		local sect = wtab:CreateSection(type(nm) == "string" and nm ~= "" and nm or nil, col)
		t._cur = adaptSection(sect)
		return t._cur
	end

	-- tab-level element methods route into the current section (the old UI was
	-- flat: elements sat directly on tabs)
	local function cur()
		if not t._cur then t:CreateSection({ name = "Features" }) end
		return t._cur
	end
	function t:CreateToggle(o) return cur():CreateToggle(o) end
	function t:CreateSlider(o) return cur():CreateSlider(o) end
	function t:CreateDropdown(o) return cur():CreateDropdown(o) end
	function t:CreateButton(o, cb) return cur():CreateButton(o, cb) end
	function t:CreateInput(o) return cur():CreateInput(o) end

	function t:Divider() end
	function t:Space() end

	return t
end

local window = {}
window._raw = WindowRaw
window._tabIcons = { Farm = "⚡", Upgrades = "⬆️", Misc = "🎁", Teleports = "🗺️", Configs = "💾", Credits = "ℹ️" }
function window:CreateTab(o)
	return adaptTab(WindowRaw:CreateTab(o.name, self._tabIcons[o.name]))
end
function window:Notify(o)
	return WindowRaw:Notify(
		o.title or o.Title or "Liquid Hub",
		o.content or o.Content or "",
		o.duration or o.Duration or 3
	)
end
local function notify(title, content, dur)
	pcall(function()
		window:Notify({ title = title, content = content, duration = dur or 3 })
	end)
	print("[LiquidHub] " .. title .. " - " .. content)
end

-- ===================== SHARED FARM STATE =====================
local Flags = {
	AutoUpgrades = false,
	AutoFragments = false,
	AutoRubins = false,
	AutoPrestige = false,
	AutoChests = false,
	AutoSquares = false,
}
local STATE2 = {
	ChestSelection = getFlag("ChestSelection") or "All Chests",
	ReturnToStart = false,
	FragInterval = 0.2,
	UpInterval = 0.2,
	RubinsInterval = 1.5,
	ZoneTarget = "Aura",
	SquaresGlideSpeed = 150,
}

-- ===================== TABS (order: Farm, Upgrades, Misc, Teleports, Configs) =====================
local TabFarm = window:CreateTab({ name = "Farm" })
local TabUpgrades = window:CreateTab({ name = "Upgrades" })
local TabShop = window:CreateTab({ name = "Misc" })
local TabTele = window:CreateTab({ name = "Teleports" })
local TabCredits = window:CreateTab({ name = "Credits" })
local cfgTab = window:CreateTab({ name = "Configs" })

-- ===================== FARM TAB =====================
do
	local sqSec = TabFarm:CreateSection({ name = "Auto Farm Squares" })
	sqSec:CreateToggle({
		name = "Auto Farm Squares",
		value = false,
		callback = function(v)
			Flags.AutoSquares = v
			notify(v and "Auto Farm Squares Enabled" or "Auto Farm Squares Disabled", v and "Gliding to squares..." or "Stopped")
		end,
	})
	sqSec:CreateSlider({
		name = "Glide Speed",
		range = { 30, 300 },
		increment = 10,
		value = 150,
		callback = function(v) STATE2.SquaresGlideSpeed = v end,
		noreg = true,
	})

	local chestSec = TabFarm:CreateSection({ name = "Auto Chests" })

	chestSec:CreateToggle({
		name = "Auto Chests",
		value = Flags.AutoChests,
		callback = function(v)
			Flags.AutoChests = v
			notify(v and "Auto Chests Enabled" or "Auto Chests Disabled", v and "Collecting..." or "Stopped")
		end,
	})

	chestSec:CreateDropdown({
		name = "Chest Selection",
		options = { "All Chests", "Normal Chests Only", "Mythic Chest Only" },
		value = STATE2.ChestSelection,
		callback = function(v)
			STATE2.ChestSelection = v
			setFlag("ChestSelection", v)
		end,
		noreg = true,
	})

	chestSec:CreateToggle({
		name = "Return to Start",
		value = STATE2.ReturnToStart,
		callback = function(v)
			STATE2.ReturnToStart = v
			notify(v and "Return Enabled" or "Return Disabled")
		end,
		noreg = true,
	})

	local fragSec = TabFarm:CreateSection({ name = "Auto Fragments" })
	fragSec:CreateToggle({
		name = "Auto Fragments Click",
		value = Flags.AutoFragments,
		callback = function(v)
			Flags.AutoFragments = v
			notify(v and "Fragments Enabled" or "Fragments Disabled", "")
		end,
	})
	fragSec:CreateSlider({
		name = "Fragments Interval",
		range = { 0.03, 1 },
		increment = 0.05,
		value = STATE2.FragInterval,
		callback = function(v) STATE2.FragInterval = v end,
		noreg = true,
	})

	local rubSec = TabFarm:CreateSection({ name = "Auto Rubins" })
	rubSec:CreateToggle({
		name = "Auto Rubins Exchange",
		value = Flags.AutoRubins,
		callback = function(v)
			Flags.AutoRubins = v
			notify(v and "Rubins Enabled" or "Rubins Disabled")
		end,
	})
	rubSec:CreateSlider({
		name = "Rubins Interval",
		range = { 0.5, 10 },
		increment = 0.5,
		value = STATE2.RubinsInterval,
		callback = function(v) STATE2.RubinsInterval = v end,
		noreg = true,
	})

	local presSec = TabFarm:CreateSection({ name = "Auto Prestige" })
	presSec:CreateToggle({
		name = "Auto Prestige",
		value = Flags.AutoPrestige,
		callback = function(v)
			Flags.AutoPrestige = v
			notify(v and "Auto Prestige Enabled" or "Auto Prestige Disabled")
		end,
	})

end

STATE.onCleanup(function()
	Flags.AutoFragments = false
	Flags.AutoRubins = false
	Flags.AutoUpgrades = false
	Flags.AutoPrestige = false
	Flags.AutoChests = false
	Flags.AutoSquares = false
	print("[LiquidHub] loops cleaned GEN=" .. STATE.GEN)
end)

-- ===================== FARM LOOPS (1:1 from ChessInc) =====================
-- Auto Fragments: task.wait directly so the interval slider applies live
-- (the fixed-interval loop() runner can't go below its 0.1s poll granularity)
task.spawn(function()
	while STATE.alive() do
		if Flags.AutoFragments and FragmentsClick then
			pcall(function() FragmentsClick:FireServer() end)
		end
		task.wait(math.max(0.03, tonumber(STATE2.FragInterval) or 0.2))
	end
end)

-- Auto Rubins: task.wait directly so the interval slider applies live
task.spawn(function()
	while STATE.alive() do
		if Flags.AutoRubins and RubinsExchangeRequest then
			pcall(function() RubinsExchangeRequest:InvokeServer(1) end)
		end
		task.wait(math.max(0.5, tonumber(STATE2.RubinsInterval) or 1.5))
	end
end)

-- Auto Prestige
loop("AutoPrestige", 2, function()
	if Flags.AutoPrestige and PrestigeRequest then
		local ok, res = pcall(function() return PrestigeRequest:InvokeServer("State") end)
		if ok and res and res.State and res.State.CanPrestige then
			pcall(function() PrestigeRequest:InvokeServer("Prestige") end)
			notify("Prestige", "Prestiged!", 3)
		end
	end
end)

-- ===================== AUTO FARM SQUARES =====================
-- Squares spawn inside the Squares zone (workspace.UpgradesFolder.Squares,
-- SquareZoneSpawn part). The server tracks every live square: polling
-- SquaresStateRequest returns { Unlocked, MaxItems, Radius, Squares = { {Id,
-- Position, Mutated}, ... } }. Collection is proximity-based: standing within
-- the magnet radius (~8 + upgrade level) of a square collects it automatically.
-- So the farm anchors at the zone and tween-glides from square to square —
-- no teleporting, the character visibly flies to each one.
do
	local TweenService = game:GetService("TweenService")
	local lp2 = Players.LocalPlayer
	local sqTween, sqTarget, sqWasOn, sqAnchored = nil, nil, false, false
	local sqSettle = 0

	local function getHrp2()
		local char = lp2.Character
		return char and char:FindFirstChild("HumanoidRootPart")
	end

	local function sqRelease(hrp)
		if sqTween then
			pcall(function() sqTween:Cancel() end)
			sqTween = nil
		end
		sqTarget = nil
		if hrp then
			hrp.AssemblyLinearVelocity = Vector3.zero
			hrp.Anchored = false
			pcall(function()
				local hum = hrp.Parent and hrp.Parent:FindFirstChildOfClass("Humanoid")
				if hum then hum:ChangeState(Enum.HumanoidStateType.GettingUp) end
			end)
		end
		sqAnchored = false
	end
	STATE.onCleanup(function()
		sqRelease(getHrp2())
	end)

	-- zone anchor: the center of the spawn platform (squares only beach inside it)
	local sqRayParams = RaycastParams.new()
	sqRayParams.FilterType = Enum.RaycastFilterType.Exclude
	local function groundYAt(x, z, fallbackY)
		local char = Players.LocalPlayer.Character
		if char then sqRayParams.FilterDescendantsInstances = { char } end
		local hit = workspace:Raycast(Vector3.new(x, (fallbackY or 0) + 15, z), Vector3.new(0, -60, 0), sqRayParams)
		return hit and hit.Position.Y or fallbackY
	end
	local function zoneCenter()
		local uf = workspace:FindFirstChild("UpgradesFolder")
		local sq = uf and uf:FindFirstChild("Squares")
		local z = sq and sq:FindFirstChild("SquareZoneSpawn")
		return z and z:IsA("BasePart") and z.Position or nil
	end

	loop("AutoFarmSquares", 0.2, function()
		local on = Flags.AutoSquares
		local hrp = getHrp2()
		if not on then
			if sqWasOn then
				sqWasOn = false
				sqRelease(hrp)
			end
			return
		end
		if not hrp then return end
		sqWasOn = true

		-- live square list from the server
		local ok, st = pcall(function()
			return Remotes.SquaresStateRequest:InvokeServer()
		end)
		if not ok or type(st) ~= "table" or not st.Unlocked then return end
		local list = st.Squares
		if type(list) ~= "table" then return end

		-- nearest live square to the character
		local best, bd
		for _, s in ipairs(list) do
			local p = s and s.Position
			if p then
				local d = (p - hrp.Position).Magnitude
				if not bd or d < bd then best, bd = p, d end
			end
		end

		-- target: nearest square, else the zone center (stay in the zone so
		-- freshly spawned squares are always close). The glide Y is the GROUND
		-- height under the square + 3 (HRP center above feet): squares sit ON
		-- the floor (Y=-0.7) and the collection check is 3D — gliding at the
		-- square's own Y + 3 offset flies OVER it and collects nothing.
		local dest
		if best then
			local gy = groundYAt(best.X, best.Z, best.Y)
			dest = Vector3.new(best.X, (gy or best.Y) + 3, best.Z)
		else
			local zc = zoneCenter()
			if zc then
				dest = Vector3.new(zc.X, groundYAt(zc.X, zc.Z, zc.Y) + 3, zc.Z)
			else
				dest = hrp.Position
			end
		end

		-- arrived: unanchor so the character SETTLES onto the square — the
		-- collection check only fires for a grounded, non-anchored character
		-- (verified live: anchored placement collects nothing, settling collects)
		local arriveRadius = 3.5
		local dist = (dest - hrp.Position).Magnitude
		if dist <= arriveRadius then
			if sqAnchored then
				hrp.Anchored = false
				sqAnchored = false
				sqSettle = 0.6 -- give gravity this long to land the character
			end
			-- while settled on the square, stay put until the magnet takes it
			sqTarget = nil
			return
		end

		-- glide: anchor + Linear tween at Glide Speed studs/sec; re-target only
		-- when the tween completes or the target changed enough to matter (12+
		-- studs) so the flight doesn't jitter as the server list refreshes
		if not sqAnchored then
			if sqSettle > 0 then
				sqSettle = sqSettle - 0.2 -- still settling from the last arrival
				return
			end
			hrp.AssemblyLinearVelocity = Vector3.zero
			hrp.Anchored = true
			sqAnchored = true
		end
		local tweenDone = (not sqTween) or sqTween.PlaybackState == Enum.PlaybackState.Completed
		if sqTarget ~= dest and not tweenDone then
			local moved = sqTarget and (sqTarget - dest).Magnitude or math.huge
			if moved < 12 then
				dest = sqTarget -- keep gliding to the old point; next tick handles the rest
			end
		end
		if sqTarget ~= dest or tweenDone then
			sqTarget = dest
			if sqTween then
				pcall(function() sqTween:Cancel() end)
				sqTween = nil
			end
			local speed = math.max(20, tonumber(STATE2.SquaresGlideSpeed) or 150)
			sqTween = TweenService:Create(hrp,
				TweenInfo.new(math.max(0.05, dist / speed), Enum.EasingStyle.Linear),
				{ CFrame = CFrame.new(dest) })
			sqTween:Play()
		end
	end)
end

-- Auto Chests farm: mythic first (global instant), then normal private, with return
do
	local function tryCollect(id)
		if Collect then
			pcall(function() Collect:FireServer(id) end)
			task.wait(0.2)
			if not workspace:FindFirstChild("ClientChests") or not workspace.ClientChests:FindFirstChild("Chest_" .. id) then return true end
			pcall(function() Collect:FireServer(tostring(id)) end)
			task.wait(0.2)
			if not workspace.ClientChests:FindFirstChild("Chest_" .. id) then return true end
			pcall(function() Collect:FireServer() end)
			task.wait(0.2)
			if not workspace.ClientChests:FindFirstChild("Chest_" .. id) then return true end
		end
		return false
	end
	loop("AutoChests", 1, function()
		if not Flags.AutoChests then return end
		local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
		if not hrp then return end
		local startPos = hrp.CFrame
		local did = false
		-- Mythic FIRST - global, must be instant
		if STATE2.ChestSelection ~= "Normal Chests Only" and RS:GetAttribute("GlobalChestActive") == true then
			local globalFolder = workspace:FindFirstChild("GlobalChestClient")
			if globalFolder then
				local gc = globalFolder:FindFirstChild("GlobalChest")
				if gc then
					local gpos
					pcall(function() gpos = gc:GetPivot().Position end)
					if gpos then
						local humM = hrp.Parent and hrp.Parent:FindFirstChildOfClass("Humanoid")
						if not humM or humM.MoveDirection.Magnitude < 0.15 then
							did = true
							pcall(function() hrp.CFrame = CFrame.new(gpos + Vector3.new(0, 4, 0)) end)
							task.wait(0.4)
							local gid = RS:GetAttribute("GlobalChestId")
							if gid and Collect then pcall(function() Collect:FireServer(gid) end) task.wait(0.2) pcall(function() Collect:FireServer(tostring(gid)) end) task.wait(0.2) pcall(function() Collect:FireServer() end) task.wait(0.2) end
							task.wait(0.3)
						end
					end
				end
			end
		end
		-- Normal chests - private, only if mythic not just done (to avoid double TP)
		if STATE2.ChestSelection ~= "Mythic Chest Only" then
			local mythicActive = RS:GetAttribute("GlobalChestActive") == true and STATE2.ChestSelection ~= "Normal Chests Only" and workspace:FindFirstChild("GlobalChestClient") and workspace.GlobalChestClient:FindFirstChild("GlobalChest")
			if not mythicActive then
				local chestsFolder = workspace:FindFirstChild("ClientChests")
				if chestsFolder then
					for _, chest in ipairs(chestsFolder:GetChildren()) do
						if not Flags.AutoChests or not STATE.alive() then break end
						-- If mythic spawns mid-loop, break and handle it next cycle
						if RS:GetAttribute("GlobalChestActive") == true and STATE2.ChestSelection ~= "Normal Chests Only" and workspace:FindFirstChild("GlobalChestClient") and workspace.GlobalChestClient:FindFirstChild("GlobalChest") then break end
						local id = tonumber(chest.Name:match("%d+"))
						if not id then continue end
						local chestPos
						pcall(function() chestPos = chest:GetPivot().Position end)
						if not chestPos then continue end
						do
							local hum = hrp.Parent and hrp.Parent:FindFirstChildOfClass("Humanoid")
							if hum and hum.MoveDirection.Magnitude > 0.15 then continue end
						end
						task.wait(1)
						if not Flags.AutoChests then break end
						pcall(function() hrp.CFrame = CFrame.new(chestPos + Vector3.new(0, 3, 0)) end)
						task.wait(0.5)
						local collected = tryCollect(id)
						if not collected then
							for _ = 1, 2 do
								if not Flags.AutoChests then break end
								local hum2 = hrp.Parent and hrp.Parent:FindFirstChildOfClass("Humanoid")
								if hum2 and hum2.MoveDirection.Magnitude > 0.15 then break end
								pcall(function() hrp.CFrame = CFrame.new(chestPos + Vector3.new(math.random(-1, 1), 0, math.random(-1, 1))) end)
								task.wait(0.4)
								if not workspace.ClientChests:FindFirstChild("Chest_" .. id) then break end
							end
						end
						did = true
						task.wait(0.5)
					end
				end
			end
		end
		if did and STATE2.ReturnToStart and startPos then
			local hum4 = hrp.Parent and hrp.Parent:FindFirstChildOfClass("Humanoid")
			if not hum4 or hum4.MoveDirection.Magnitude < 0.1 then
				pcall(function() hrp.CFrame = startPos end)
				task.wait(0.3)
			end
		end
	end)
end

-- ===================== UPGRADES TAB =====================
local upgradeIds = { "ChessMulti", "ChessVicPointsMulti", "ClickSpeed", "GoldenChance", "MoveSpeed", "WinChance", "VicAuraMulti", "VicBooksMulti", "VicChessMulti", "VicDiamondsMulti", "VicPointsMulti", "VicRubiesMulti", "DiamondBooksMulti", "DiamondButtonSpeed", "DiamondChessMulti", "DiamondDiamondsMulti", "DiamondMoreBulk", "DiamondMoreDiamonds", "DiamondRubiesMulti", "BookAuraMulti", "BookBooksMulti", "BookButtonSpeed", "BookMoreKeys", "BookRuneLuck", "BookRuneSpeed", "AuraAuraMulti", "AuraAuraSpeed", "AuraChessMulti", "AuraMoreAura", "AuraMoreBulk", "AuraRuneLuck", "AuraStatsMulti", "SquaresAuraMulti", "SquaresChessMulti", "SquaresFragmentsMulti", "SquaresMagnetRange", "SquaresMaxItems", "SquaresMulti", "SquaresMutationChance", "SquaresSpawnRate", "SquaresVicPointsMulti", "FragmentAutoClicker", "FragmentBulkMulti", "FragmentClickSpeed", "FragmentDuplicateChance", "FragmentFragmentsMulti", "FragmentMoreFragments", "RubinBooksMulti", "RubinChessMulti", "RubinDiamondsMulti", "RubinKeysChance", "RubinMoreBulk", "RubinRubiesMulti" }
local selectedUpgrades = { "ChessMulti" }
local buyMode = "Buy"

do
	local selSec = TabUpgrades:CreateSection({ name = "Auto Buy Upgrades" })

	local selectUpgradesDD = selSec:CreateDropdown({
		name = "Select Upgrades",
		options = upgradeIds,
		value = { "ChessMulti" },
		multiSelect = true,
		callback = function(val)
			if type(val) == "table" then
				selectedUpgrades = val
			elseif type(val) == "string" then
				selectedUpgrades = { val }
			elseif val == nil then
				selectedUpgrades = {}
			end
			if selectedUpgrades and #selectedUpgrades > 0 then
				print("[LiquidHub] selected " .. table.concat(selectedUpgrades, ", "))
			else
				print("[LiquidHub] selected none")
			end
		end,
		noreg = true,
	})

	selSec:CreateButton("Select All / Deselect All", function()
		if selectedUpgrades and #selectedUpgrades == #upgradeIds then
			selectedUpgrades = {}
			pcall(function() selectUpgradesDD.Set({}) end)
			notify("Upgrades", "Deselected all", 2)
		else
			selectedUpgrades = {}
			for _, id in ipairs(upgradeIds) do table.insert(selectedUpgrades, id) end
			pcall(function() selectUpgradesDD.Set(upgradeIds) end)
			notify("Upgrades", "Selected all (" .. #upgradeIds .. ")", 2)
		end
	end)

	selSec:CreateDropdown({
		name = "Buy Mode",
		options = { "Buy", "BuyMax" },
		value = "Buy",
		callback = function(v) buyMode = v end,
		noreg = true,
	})

	selSec:CreateToggle({
		name = "Auto Upgrade",
		value = Flags.AutoUpgrades,
		callback = function(v)
			Flags.AutoUpgrades = v
			notify(v and "Auto Upgrade Enabled" or "Auto Upgrade Disabled", "Mode: " .. buyMode)
		end,
	})

	selSec:CreateButton("Upgrade All Once", function()
		for _, id in ipairs(upgradeIds) do
			pcall(function() UpgradePurchase:InvokeServer(id, buyMode) end)
			task.wait(0.05)
		end
		notify("Upgrade All", "All upgrades attempted (" .. buyMode .. ")")
	end)

	-- Auto Upgrade loop
	loop("AutoUpgrades", 0.2, function()
		if Flags.AutoUpgrades and UpgradePurchase then
			for _, id in ipairs(selectedUpgrades) do
				pcall(function() UpgradePurchase:InvokeServer(id, buyMode) end)
				task.wait(0.05)
			end
		end
	end)
end

-- ===================== MOVEMENT / UTILITIES / FLIGHT (same as Sticks_Inc2_) =====================
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local function getHumanoid()
	local char = Players.LocalPlayer.Character
	return char and char:FindFirstChildOfClass("Humanoid")
end

local function setNoclip(on)
	pcall(function()
		local char = Players.LocalPlayer.Character
		if not char then return end
		for _, v in ipairs(char:GetDescendants()) do
			if v:IsA("BasePart") then
				v.CanCollide = not on
			end
		end
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if hrp then hrp.CanCollide = not on end
	end)
end

-- Hide Name
local function applyHideName(on)
	local char = Players.LocalPlayer.Character
	if char then
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.NameDisplayDistance = on and 0 or 100
			if on then hum.DisplayName = "" else hum.DisplayName = Players.LocalPlayer.DisplayName end
		end
		for _, gui in ipairs(char:GetDescendants()) do
			if gui:IsA("BillboardGui") then
				if on then
					if gui:GetAttribute("HideName_OrigEnabled") == nil then
						gui:SetAttribute("HideName_OrigEnabled", gui.Enabled)
					end
					gui.Enabled = false
				else
					local orig = gui:GetAttribute("HideName_OrigEnabled")
					gui.Enabled = (orig ~= nil and orig) or true
					pcall(function() gui:SetAttribute("HideName_OrigEnabled", nil) end)
				end
				for _, lbl in ipairs(gui:GetDescendants()) do
					if lbl:IsA("TextLabel") then
						if on then
							if lbl:GetAttribute("HideName_OrigVis") == nil then
								lbl:SetAttribute("HideName_OrigVis", lbl.Visible)
							end
							lbl.Visible = false
							lbl.TextTransparency = 1
						else
							local v = lbl:GetAttribute("HideName_OrigVis")
							lbl.Visible = (v ~= nil and v) or true
							lbl.TextTransparency = 0
							pcall(function() lbl:SetAttribute("HideName_OrigVis", nil) end)
						end
					end
				end
			end
		end
	end
	pcall(function()
		local p = Players.LocalPlayer
		local pname, dname = p.Name, p.DisplayName
		local function hideInGui(gui)
			for _, d in ipairs(gui:GetDescendants()) do
				if d:IsA("TextLabel") or d:IsA("TextButton") then
					local txt = d.Text
					if txt == pname or txt == dname or txt == "@" .. pname or txt:find(pname, 1, true) then
						d.Visible = not on
					end
				end
			end
		end
		for _, gui in ipairs({ Players.LocalPlayer:FindFirstChild("PlayerGui"), game.CoreGui }) do
			if gui then hideInGui(gui) end
		end
	end)
end

local hideNameOn = getFlag("HideNameOn")
local noclipOn = getFlag("NoclipOn")
local noclipRunning = false
local function noclipLoop()
	noclipRunning = true
	while getFlag("NoclipOn") and isCurrentGen() do
		pcall(function() setNoclip(true) end)
		task.wait(0.2)
	end
	pcall(function() setNoclip(false) end)
	noclipRunning = false
end

-- Walkspeed / Jump
local defaultWalkSpeed = 16
local defaultJumpHeight = 7.2
pcall(function()
	local h = getHumanoid()
	if h then
		defaultWalkSpeed = h.WalkSpeed
		defaultJumpHeight = h.UseJumpPower and h.JumpPower or h.JumpHeight
	end
end)

local currentWalkSpeed = getFlag("WalkSpeed") or defaultWalkSpeed
if type(currentWalkSpeed) ~= "number" then currentWalkSpeed = defaultWalkSpeed end
local currentJump = getFlag("JumpHeight") or defaultJumpHeight
if type(currentJump) ~= "number" then currentJump = defaultJumpHeight end

local function applyWalkSpeed(v)
	currentWalkSpeed = math.clamp(tonumber(v) or defaultWalkSpeed, 8, 200)
	pcall(function() setFlag("WalkSpeed", currentWalkSpeed) end)
	local hum = getHumanoid()
	if hum then
		pcall(function() hum.WalkSpeed = currentWalkSpeed end)
	end
end

local function applyJump(v)
	currentJump = math.clamp(tonumber(v) or defaultJumpHeight, 0, 200)
	pcall(function() setFlag("JumpHeight", currentJump) end)
	local hum = getHumanoid()
	if hum then
		pcall(function()
			if hum.UseJumpPower then
				hum.JumpPower = currentJump
			else
				hum.JumpHeight = currentJump
			end
		end)
	end
end

-- keep WalkSpeed/Jump from being reset by game
task.spawn(function()
	while isCurrentGen() do
		task.wait(0.5)
		local hum = getHumanoid()
		if hum then
			if math.abs(hum.WalkSpeed - currentWalkSpeed) > 0.5 then
				pcall(function() hum.WalkSpeed = currentWalkSpeed end)
			end
			local targetJump = currentJump
			local curJump = hum.UseJumpPower and hum.JumpPower or hum.JumpHeight
			if math.abs(curJump - targetJump) > 0.5 then
				pcall(function()
					if hum.UseJumpPower then hum.JumpPower = targetJump else hum.JumpHeight = targetJump end
				end)
			end
			if hideNameOn then pcall(function() applyHideName(true) end) end
		end
		if noclipOn and not noclipRunning then task.spawn(noclipLoop) end
	end
end)

-- Fly
local flyOn = getFlag("FlyOn") or false
local flySpeed = getFlag("FlySpeed") or 60
if type(flySpeed) ~= "number" then flySpeed = 60 end
local flyBV, flyBG, flyConn
local flyKeys = { W = false, A = false, S = false, D = false, Space = false, Ctrl = false }

local function stopFly()
	flyOn = false
	pcall(function() setFlag("FlyOn", false) end)
	if flyConn then flyConn:Disconnect() flyConn = nil end
	if flyBV then flyBV:Destroy() flyBV = nil end
	if flyBG then flyBG:Destroy() flyBG = nil end
	local hum = getHumanoid()
	if hum then pcall(function() hum.PlatformStand = false end) end
	pcall(function() setNoclip(getFlag("NoclipOn")) end)
end

local function startFly()
	local char = Players.LocalPlayer.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local hum = getHumanoid()
	if not hrp or not hum then return end
	flyOn = true
	pcall(function() setFlag("FlyOn", true) end)
	pcall(function() hum.PlatformStand = true end)
	flyBG = Instance.new("BodyGyro")
	flyBG.P = 9e4
	flyBG.maxTorque = Vector3.new(9e9, 9e9, 9e9)
	flyBG.cframe = hrp.CFrame
	flyBG.Parent = hrp
	flyBV = Instance.new("BodyVelocity")
	flyBV.velocity = Vector3.new(0, 0, 0)
	flyBV.maxForce = Vector3.new(9e9, 9e9, 9e9)
	flyBV.Parent = hrp
	setNoclip(true)
	flyConn = RunService.Heartbeat:Connect(function()
		if not flyOn or not isCurrentGen() then stopFly() return end
		local char2 = Players.LocalPlayer.Character
		local hrp2 = char2 and char2:FindFirstChild("HumanoidRootPart")
		if not hrp2 or not flyBV or not flyBG then return end
		local cam = workspace.CurrentCamera
		local move = Vector3.new(0, 0, 0)
		if flyKeys.W then move += cam.CFrame.LookVector end
		if flyKeys.S then move -= cam.CFrame.LookVector end
		if flyKeys.A then move -= cam.CFrame.RightVector end
		if flyKeys.D then move += cam.CFrame.RightVector end
		if flyKeys.Space then move += Vector3.new(0, 1, 0) end
		if flyKeys.Ctrl then move -= Vector3.new(0, 1, 0) end
		if move.Magnitude > 0 then move = move.Unit * flySpeed end
		flyBV.velocity = move
		flyBG.cframe = cam.CFrame
	end)
end

-- Input for fly
UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe then return end
	local k = input.KeyCode
	if k == Enum.KeyCode.W then flyKeys.W = true
	elseif k == Enum.KeyCode.A then flyKeys.A = true
	elseif k == Enum.KeyCode.S then flyKeys.S = true
	elseif k == Enum.KeyCode.D then flyKeys.D = true
	elseif k == Enum.KeyCode.Space then flyKeys.Space = true
	elseif k == Enum.KeyCode.LeftControl then flyKeys.Ctrl = true end
end)
UserInputService.InputEnded:Connect(function(input)
	local k = input.KeyCode
	if k == Enum.KeyCode.W then flyKeys.W = false
	elseif k == Enum.KeyCode.A then flyKeys.A = false
	elseif k == Enum.KeyCode.S then flyKeys.S = false
	elseif k == Enum.KeyCode.D then flyKeys.D = false
	elseif k == Enum.KeyCode.Space then flyKeys.Space = false
	elseif k == Enum.KeyCode.LeftControl then flyKeys.Ctrl = false end
end)

-- re-apply on respawn + watch for billboard recreation
Players.LocalPlayer.CharacterAdded:Connect(function(char)
	task.wait(0.6)
	local hum = char:WaitForChild("Humanoid", 6)
	if hum then
		pcall(function() hum.WalkSpeed = currentWalkSpeed end)
		pcall(function()
			if hum.UseJumpPower then hum.JumpPower = currentJump else hum.JumpHeight = currentJump end
		end)
	end
	if hideNameOn then task.wait(0.2) applyHideName(true) end
	if flyOn then task.wait(0.2) startFly() end
	char.DescendantAdded:Connect(function(obj)
		if hideNameOn and obj:IsA("BillboardGui") then
			task.wait(0.05)
			if getFlag("HideNameOn") then applyHideName(true) end
		end
	end)
end)
pcall(function()
	local curChar = Players.LocalPlayer.Character
	if curChar then
		curChar.DescendantAdded:Connect(function(obj)
			if getFlag("HideNameOn") and obj:IsA("BillboardGui") then
				task.wait(0.05)
				applyHideName(true)
			end
		end)
	end
end)

-- ===================== MISC TAB =====================
do
	local knownCodes = { "SorryForThat", "3kccu", "5kFavs", "500ccu", "150ccu", "RELEASE", "REBALANCE", "Frog", "1MVisits", "100KVisits", "30KVisits", "100Likes", "100ccu", "1kLikes" }

	-- Movement
	local moveSec = TabShop:CreateSection({ name = "Movement" })
	moveSec:CreateSlider({
		name = "Walkspeed",
		range = { 8, 200 },
		increment = 1,
		value = currentWalkSpeed,
		callback = function(v) applyWalkSpeed(v) end,
	})
	moveSec:CreateSlider({
		name = "Jumpheight",
		range = { 0, 200 },
		increment = 1,
		value = currentJump,
		callback = function(v) applyJump(v) end,
	})

	-- Utilities
	local utilSec = TabShop:CreateSection({ name = "Utilities" })
	utilSec:CreateToggle({
		name = "Hide Name",
		value = hideNameOn,
		callback = function(v)
			hideNameOn = v
			setFlag("HideNameOn", v)
			applyHideName(v)
		end,
	})
	utilSec:CreateToggle({
		name = "Noclip",
		value = noclipOn,
		callback = function(v)
			noclipOn = v
			setFlag("NoclipOn", v)
			if v then
				if not noclipRunning then task.spawn(noclipLoop) end
			else
				setNoclip(false)
			end
		end,
	})

	-- Flight
	local flySec = TabShop:CreateSection({ name = "Flight" })
	flySec:CreateToggle({
		name = "Fly",
		value = flyOn,
		callback = function(v)
			if v then startFly() else stopFly() end
		end,
	})
	flySec:CreateSlider({
		name = "Fly Speed",
		range = { 10, 250 },
		increment = 5,
		value = flySpeed,
		callback = function(v)
			flySpeed = math.clamp(tonumber(v) or 60, 10, 250)
			pcall(function() setFlag("FlySpeed", flySpeed) end)
		end,
	})

	-- init from saved flags
	if hideNameOn then applyHideName(true) end
	if noclipOn and not noclipRunning then task.spawn(noclipLoop) end
	if flyOn then task.defer(function() task.wait(0.8) if getFlag("FlyOn") then startFly() end end) end

	local codeSec = TabShop:CreateSection({ name = "Codes" })
	codeSec:CreateButton("Redeem All Codes", function()
		task.spawn(function()
			for _, code in ipairs(knownCodes) do
				local ok, res = pcall(function() return ShopRedeemCode:InvokeServer(code) end)
				local msg = ok and (res.Success and "Success" or tostring(res.Reason)) or "Error"
				notify("Code: " .. code, msg, 2)
				task.wait(0.65)
			end
			notify("Codes", "All codes processed")
		end)
	end)

	-- ===================== ANTI-AFK (same as Sticks_Inc2_) =====================
	local afkSec = TabShop:CreateSection({ name = "Session" })
	afkSec:CreateToggle({
		name = "Anti-AFK",
		value = false,
		callback = function(v) setFlag("AntiAFK", v) end,
	})
	-- Two layers: (1) if the game ships an idle-rejoin remote (Sticks-style),
	-- poke it on a timer; (2) universal fallback — on the client's Idled signal,
	-- simulate input via VirtualUser so Roblox's own ~20-min idle kick never
	-- fires. The Idled connection is made ONCE (connecting it inside a loop
	-- would stack a new handler every cycle); the flag gates whether it acts.
	pcall(function()
		local vu = game:GetService("VirtualUser")
		LocalPlayer.Idled:Connect(function()
			if not getFlag("AntiAFK") then return end
			vu:CaptureController()
			vu:ClickButton2(Vector2.new())
		end)
	end)
	loop("AntiAFK", 240, function()
		if not getFlag("AntiAFK") then return end
		pcall(function()
			local net = RS:FindFirstChild("IdleAutoRejoinNetwork")
			if net and net:FindFirstChild("Activity") then
				net.Activity:FireServer("Activity")
			end
		end)
	end)
end

-- ===================== TELEPORTS TAB =====================
do
	local zoneSec = TabTele:CreateSection({ name = "Zones" })
	zoneSec:CreateDropdown({
		name = "Select Zone",
		options = { "Aura", "Books", "Diamonds", "Rubins", "Fragments", "Squares" },
		value = STATE2.ZoneTarget,
		callback = function(v) STATE2.ZoneTarget = v end,
		noreg = true,
	})
	zoneSec:CreateButton("Teleport To Zone", function()
		local zone = workspace:FindFirstChild("UpgradesFolder") and workspace.UpgradesFolder:FindFirstChild(STATE2.ZoneTarget)
		local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
		if zone and hrp then
			local dest = nil
			for _, d in ipairs(zone:GetDescendants()) do
				if d:IsA("BasePart") then dest = d break end
			end
			if dest then
				hrp.CFrame = CFrame.new(dest.Position + Vector3.new(0, 5, 0))
				notify("Zone", "Teleported to " .. STATE2.ZoneTarget)
			else
				notify("Zone", "No part found")
			end
		else
			notify("Teleport", "Failed")
		end
	end)
	zoneSec:CreateButton("Back To Spawn", function()
		local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
		if hrp then
			hrp.CFrame = CFrame.new(0, 5, 0)
			notify("Teleport", "Back to spawn")
		end
	end)
end

-- ===================== CREDITS =====================
local DISCORD_INVITE = "https://discord.gg/PGyk3JcKht"
local SCRIPT_VERSION = "1.0.0"
do
	-- column 1: team + community
	local teamSec = TabCredits:CreateSection({ name = "Team", column = 1 })
	teamSec:CreateLabel("Owner • sempai.real")
	teamSec:CreateLabel("Game: " .. GAME_NAME)
	local commSec = TabCredits:CreateSection({ name = "Community", column = 1 })
	commSec:CreateButton("Discord Server", function()
		pcall(function() setclipboard(DISCORD_INVITE) end)
		notify("Discord", "Invite copied!")
	end)
	-- column 2: about
	local aboutSec = TabCredits:CreateSection({ name = "About", column = 2 })
	aboutSec:CreateLabel("Script " .. SCRIPT_VERSION)
	aboutSec:CreateLabel("Liquid Hub v2.3")
	aboutSec:CreateLabel("Report bugs in Discord")
end

-- ===================== CONFIGS =====================
-- Named setups saved to files + optional autoload; same JSON format as the
-- other Liquid Hub scripts, folder ChessInc so configs don't clash.
do
	local CF_DIR = "ChessInc/configs"
	local AUTOLOAD_FILE = "ChessInc/autoload.txt"
	local Http = game:GetService("HttpService")

	local canIO = typeof(writefile) == "function" and typeof(readfile) == "function"
		and typeof(isfile) == "function" and typeof(makefolder) == "function"

	local function ensureDir()
		if not canIO then return false end
		local ok = pcall(function()
			makefolder("ChessInc")
			makefolder(CF_DIR)
		end)
		return ok
	end
	local function cfgPath(name) return CF_DIR .. "/" .. name .. ".json" end
	local function safeName(name)
		name = tostring(name or ""):match("^%s*(.-)%s*$")
		if not name or name == "" then return nil end
		if name:find("[/\\]") then return nil end
		if #name > 40 then name = name:sub(1, 40) end
		return name
	end
	local function listConfigs()
		local out = {}
		if not canIO then return out end
		pcall(function()
			for _, p in ipairs(listfiles(CF_DIR)) do
				local n = p:match("([^/\\]+)%.json$")
				if n then out[#out + 1] = n end
			end
		end)
		table.sort(out)
		return out
	end
	local function snapshot()
		local data = {}
		for k, e in pairs(Reg) do
			if e.kind == "toggle" and type(e.current) == "boolean" then
				data[k] = { t = "b", v = e.current }
			elseif e.kind == "slider" and type(e.current) == "number" then
				data[k] = { t = "n", v = e.current }
			elseif e.kind == "dropdown" then
				local v = e.current
				if type(v) == "string" or type(v) == "table" then
					data[k] = { t = "d", v = v }
				end
			end
		end
		-- main-hub flags + intervals are persisted too (the _Flags block,
		-- same idea as the original ChessInc snapshot)
		data["_Flags"] = { t = "f", v = {
			AutoChests = Flags.AutoChests,
			AutoFragments = Flags.AutoFragments,
			AutoRubins = Flags.AutoRubins,
			AutoPrestige = Flags.AutoPrestige,
			AutoUpgrades = Flags.AutoUpgrades,
			ChestSelection = STATE2.ChestSelection,
			ReturnToStart = STATE2.ReturnToStart,
			FragInterval = STATE2.FragInterval,
			UpInterval = STATE2.UpInterval,
			RubinsInterval = STATE2.RubinsInterval,
			SelectedUpgrades = selectedUpgrades,
			BuyMode = buyMode,
		} }
		return data
	end
	local function applyData(data)
		if type(data) ~= "table" then return 0 end
		local n = 0
		for k, sv in pairs(data) do
			if k == "_Flags" and sv.t == "f" and type(sv.v) == "table" then
				local f = sv.v
				if type(f.AutoChests) == "boolean" then Flags.AutoChests = f.AutoChests end
				if type(f.AutoFragments) == "boolean" then Flags.AutoFragments = f.AutoFragments end
				if type(f.AutoRubins) == "boolean" then Flags.AutoRubins = f.AutoRubins end
				if type(f.AutoPrestige) == "boolean" then Flags.AutoPrestige = f.AutoPrestige end
				if type(f.AutoUpgrades) == "boolean" then Flags.AutoUpgrades = f.AutoUpgrades end
				if type(f.ChestSelection) == "string" then STATE2.ChestSelection = f.ChestSelection end
				if type(f.ReturnToStart) == "boolean" then STATE2.ReturnToStart = f.ReturnToStart end
				if type(f.FragInterval) == "number" then STATE2.FragInterval = f.FragInterval end
				if type(f.UpInterval) == "number" then STATE2.UpInterval = f.UpInterval end
				if type(f.RubinsInterval) == "number" then STATE2.RubinsInterval = f.RubinsInterval end
				if type(f.SelectedUpgrades) == "table" then selectedUpgrades = f.SelectedUpgrades end
				if type(f.BuyMode) == "string" then buyMode = f.BuyMode end
				n = n + 1
			else
				local e = Reg[k]
				if e and type(sv) == "table" and sv.t then
					local okType = false
					if sv.t == "b" and e.kind == "toggle" and type(sv.v) == "boolean" then
						okType = true
					elseif sv.t == "n" and e.kind == "slider" and type(sv.v) == "number" then
						okType = true
					elseif sv.t == "d" and e.kind == "dropdown"
						and (type(sv.v) == "string" or type(sv.v) == "table") then
						okType = true
					end
					if okType then
						pcall(e.apply, sv.v)
						n = n + 1
					end
				end
			end
		end
		return n
	end
	local function getAutoload()
		if not canIO then return nil end
		local ok, txt = pcall(function() return readfile(AUTOLOAD_FILE) end)
		if not ok or type(txt) ~= "string" then return nil end
		return safeName(txt)
	end
	local function setAutoload(name)
		if not canIO then return false end
		ensureDir()
		local ok = pcall(function() writefile(AUTOLOAD_FILE, name) end)
		return ok
	end
	local function clearAutoload()
		if not canIO then return end
		pcall(function() delfile(AUTOLOAD_FILE) end)
	end

	-- File management
	local fileSec = cfgTab:CreateSection({ name = "Config Files" })
	fileSec:CreateLabel(canIO and "Ready • File I/O available" or "File functions missing — executor unsupported")

	local pendingName = ""
	fileSec:CreateInput({
		name = "Config Name",
		placeholder = "my setup (no slashes)",
		callback = function(v) pendingName = tostring(v or "") end,
		noreg = true,
	})

	local selected = nil
	local listDD = fileSec:CreateDropdown({
		name = "Saved Configs",
		options = {},
		value = nil,
		callback = function(v)
			if type(v) == "table" then selected = v[1] else selected = v end
		end,
		noreg = true,
	})

	local function refreshList()
		local names = listConfigs()
		pcall(function() listDD.Refresh(names) end)
		if selected and not table.find(names, selected) then selected = nil end
		return names
	end

	-- Actions
	local actSec = cfgTab:CreateSection({ name = "Actions" })

	actSec:CreateButton("Save Current Setup", function()
		local name = safeName(pendingName)
		if not name then window:Notify({ title = "Configs", content = "Type a config name first" }) return end
		if not canIO then window:Notify({ title = "Configs", content = "File functions missing" }) return end
		ensureDir()
		local ok = pcall(function()
			writefile(cfgPath(name), Http:JSONEncode(snapshot()))
		end)
		if ok then
			refreshList()
			listDD.Set(name)
			selected = name
			window:Notify({ title = "Configs", content = "Saved " .. name })
		else
			window:Notify({ title = "Configs", content = "Save failed" })
		end
	end)

	actSec:CreateButton("Load Selected", function()
		if not selected then window:Notify({ title = "Configs", content = "Select a config first" }) return end
		local ok, txt = pcall(function() return readfile(cfgPath(selected)) end)
		if not ok or type(txt) ~= "string" then window:Notify({ title = "Configs", content = "Read failed" }) return end
		local ok2, data = pcall(function() return Http:JSONDecode(txt) end)
		if not ok2 or type(data) ~= "table" then window:Notify({ title = "Configs", content = "Bad file" }) return end
		local n = applyData(data)
		window:Notify({ title = "Configs", content = "Loaded " .. selected .. " (" .. n .. ")" })
	end)

	actSec:CreateButton("Delete Selected", function()
		if not selected then window:Notify({ title = "Configs", content = "Select a config first" }) return end
		pcall(function() delfile(cfgPath(selected)) end)
		if getAutoload() == selected then clearAutoload() end
		selected = nil
		refreshList()
		listDD.Set(nil)
		window:Notify({ title = "Configs", content = "Deleted" })
	end)

	-- ===================== THEMES =====================
	local themeSec = cfgTab:CreateSection({ name = "Theme" })
	themeSec:CreateDropdown({
		name = "UI Theme",
		options = { "Ocean", "Midnight", "Aqua", "Blood" },
		value = "Ocean",
		callback = function(choice)
			if type(choice) == "string" then
				pcall(function() WindowRaw:SetTheme(choice) end)
			end
		end,
		noreg = true,
	})

	-- Autoload
	local autoSec = cfgTab:CreateSection({ name = "Autoload" })
	local autoT -- forward declaration: the callback must close over the local
	autoT = autoSec:CreateToggle({
		name = "Autoload Selected on Start",
		value = false,
		callback = function(v)
			if v then
				if not selected then
					window:Notify({ title = "Configs", content = "Select a config first" })
					autoT.Set(false)
					return
				end
				if setAutoload(selected) then
					window:Notify({ title = "Configs", content = "Autoload: " .. selected })
				else
					window:Notify({ title = "Configs", content = "Autoload failed" })
				end
			else
				clearAutoload()
				window:Notify({ title = "Configs", content = "Autoload off" })
			end
		end,
		noreg = true,
	})

	local names = refreshList()
	local auto = getAutoload()
	if auto and table.find(names, auto) then
		selected = auto
		pcall(function() listDD.Set(auto) end)
		pcall(function() autoT.Set(true) end)
	end

	-- Autoload: apply a few seconds after start so the whole UI exists.
	task.delay(3, function()
		pcall(function()
			local a = getAutoload()
			if a and a ~= "" then
				local ok, txt = pcall(function() return readfile(cfgPath(a)) end)
				if ok and type(txt) == "string" then
					local ok2, data = pcall(function() return Http:JSONDecode(txt) end)
					if ok2 and type(data) == "table" then
						local n = applyData(data)
						window:Notify({ title = "Configs", content = "Autoloaded " .. a .. " (" .. n .. ")" })
					end
				end
			end
		end)
	end)
end

notify("Liquid Hub Loaded", "Press RightShift to toggle. GEN=" .. STATE.GEN, 4)
print("[LiquidHub] ChessInc Ready GEN=" .. STATE.GEN)
