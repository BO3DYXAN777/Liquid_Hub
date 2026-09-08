-- Universal Hub Loader | supports multiple games | Delta Plugin fix included
-- Key system gate added: provider selection (Work.ink / Linkvertise) + HWID binding + session cache

-- Supported: Final Swarm (99521272836282), Chess Incremental, Sticks Incremental 2

local KEY_SYSTEM_URL = "https://raw.githubusercontent.com/BO3DYXAN777/Liquid_Hub/refs/heads/main/KeySystemUI.luau" -- host KeySystemUI.luau here (same repo as your scripts)
local LOCAL_KEY_UI = "LiquidHub/KeySystemUI.luau" -- optional local copy on disk (writefile)

local SUPPORTED = {
    [99521272836282] = "https://raw.githubusercontent.com/BO3DYXAN777/Liquid_Hub/refs/heads/main/Final%20Swarm.luau", -- Final Swarm main

    [797875825749] = "https://raw.githubusercontent.com/BO3DYXAN777/Liquid_Hub/refs/heads/main/Final%20Swarm.luau", -- Final Swarm Raid

    [9551044479] = "https://raw.githubusercontent.com/BO3DYXAN777/Liquid_Hub/refs/heads/main/Final%20Swarm.luau", -- Final Swarm Universe

        [72119929635167] = "https://raw.githubusercontent.com/BO3DYXAN777/Liquid_Hub/refs/heads/main/ChessInc_.luau", -- Chess Incremental Place
    [10381920426] = "https://raw.githubusercontent.com/BO3DYXAN777/Liquid_Hub/refs/heads/main/ChessInc_.luau", -- Chess Incremental Game

    -- Sticks Incremental 2: TODO paste the real PlaceId(s) from the game URL (roblox.com/games/<PLACEID>/...)
    -- [0000000000] = "https://raw.githubusercontent.com/BO3DYXAN777/Liquid_Hub/refs/heads/main/SticksIncremental2.luau", -- Sticks Incremental 2
    -- [0000000000] = "https://raw.githubusercontent.com/BO3DYXAN777/Liquid_Hub/refs/heads/main/SticksIncremental2.luau", -- Sticks Incremental 2 (alt place)
    -- [0000000000] = "https://raw.githubusercontent.com/BO3DYXAN777/Liquid_Hub/refs/heads/main/SticksIncremental2.luau", -- Sticks Incremental 2 (universe id)

}

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

            -- Sticks Incremental 2: matched by name until real PlaceIds are added above
            url = "https://raw.githubusercontent.com/BO3DYXAN777/Liquid_Hub/refs/heads/main/SticksIncremental2.luau"

        elseif workspace:FindFirstChild("Enemies") then

            local ok, hasRaid = pcall(function()

                for _,e in ipairs(workspace.Enemies:GetChildren()) do

                    if e.Name:lower():find("raid") or e.Name:lower():find("tomb") then return true end

                end

                return false

            end)

            if ok and hasRaid then url = SUPPORTED[99521272836282] end

        end

        if not url and workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Floor") then

            local ok, hasFloor = pcall(function() return workspace.Map.Floor.Size.Magnitude > 1000 end)

            if ok and hasFloor then url = SUPPORTED[99521272836282] end

        end

    end

    if not url then

        warn("[Universal Loader] Game not supported: PlaceId="..tostring(pid).." GameId="..tostring(gid).." Name="..tostring(game.Name))

        pcall(function()

            game:GetService("StarterGui"):SetCore("SendNotification", {

                Title = "Universal Loader",

                Text = "Game not supported: "..tostring(pid),

                Duration = 5

            })

        end)

        return

    end

    --// ================= KEY SYSTEM GATE =================
    -- Check if the game is supported BEFORE showing the key UI (no point gating unsupported games)

    local function loadKeySystemUI()
        -- prefer local copy (faster, works offline), fall back to GitHub
        local okLocal, localMod = pcall(function()
            if readfile and isfile and isfile(LOCAL_KEY_UI) then
                local fn = loadstring(readfile(LOCAL_KEY_UI))
                if fn then return fn() end
            end
            error("no local copy")
        end)
        if okLocal and localMod then return localMod end

        local okRemote, remote = pcall(function()
            return loadstring(game:HttpGet(KEY_SYSTEM_URL, true))()
        end)
        if okRemote and remote then return remote end

        warn("[Universal Loader] Key system UI failed to load: "..tostring(remote))
        return nil
    end

    local KeySystemUI = loadKeySystemUI()

    local function startHub(sessionToken)
        -- sessionToken is verified by the backend; the hub itself can re-verify with /api/session/verify
        getgenv().LiquidHubSession = sessionToken
        local ok, err = pcall(function()
            loadstring(game:HttpGet(url, true))()
        end)
        if not ok then
            warn("[Universal Loader] Failed to load hub: "..tostring(err))
        end
    end

    if KeySystemUI and KeySystemUI.Run then
        KeySystemUI.Run(startHub)
    else
        -- Failsafe: if the key UI can't load, decide policy here.
        -- Option A (locked): do nothing - hub stays locked. Option B (open): startHub("offline")
        startHub("offline") -- change to nothing if you want the hub hard-locked behind the key system
    end

end)
