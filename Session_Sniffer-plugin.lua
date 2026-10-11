-- Author: IB_U_Z_Z_A_R_Dl
-- Description: Plugin for Session Sniffer project on GitHub.
-- Allows you to automatically have every usernames showing up on Session Sniffer project, by logging all players from your sessions to "Cherax\Lua\Session_Sniffer-plugin\log.txt".
-- GitHub Repository: https://github.com/BUZZARDGTA/Session_Sniffer-plugin-Cherax-Lua


-- === Globals ===
local mainLoopThread = nil
local last_logger_scan_timestamp = 0
local logged_players = {} -- Dedup set: "scid:ip:name" -> true

-- === Constants ===
local SCRIPT_NAME <const> = "Session_Sniffer-plugin.lua"
local SCRIPT_TITLE <const> = "Session Sniffer"
local SCRIPT_LOG__PATH <const> = FileMgr.GetMenuRootPath() .. "\\Lua\\Session_Sniffer-plugin\\log.txt"
local LOGGER_SCAN_INTERVAL_SECONDS <const> = 1
local NATIVE_NETWORK_IS_SESSION_STARTED <const> = 0x9DE624D2FC4B603F
local FEATURE_SESSION_SNIFFER_LOGGING_HASH <const> = Utils.Joaat("SessionSnifferLogging")

-- === Utility Functions ===
local function handle_script_exit(params)
    params = params or {}
    if params.hasScriptCrashed then
        GUI.AddToast(SCRIPT_TITLE, "Oh no... Script crashed:(\nYou gotta restart it manually.", 10000)
    end

    SetShouldUnload()
end

local function create_empty_file(filepath)
    local dir = filepath:match("^(.*)[/\\]")
    if dir then
        FileMgr.CreateDir(dir)
    end

    local file, err = io.open(filepath, "w")
    if err then
        handle_script_exit({ hasScriptCrashed = true })
        return
    end

    file:close()
end

local function read_file(file_path)
    local file, err = io.open(file_path, "r")
    if err then
        return nil, err
    end

    local content = file:read("*a")

    file:close()

    return content, nil
end

local function make_dedup_key(scid, ip, name)
    return scid .. ":" .. ip .. ":" .. name
end

-- Load existing entries once at startup to allow O(1) duplicate checks without reading disk
local function init_log_cache()
    if not FileMgr.DoesFileExist(SCRIPT_LOG__PATH) then
        create_empty_file(SCRIPT_LOG__PATH)
        return
    end

    local content, err = read_file(SCRIPT_LOG__PATH)
    if err or not content then
        return
    end

    for line in content:gmatch("[^\r\n]+") do
        local name, scid, ip = line:match("^user:(.-), scid:(%d+), ip:([%d%.]+)")
        if name and scid and ip then
            logged_players[make_dedup_key(scid, ip, name)] = true
        end
    end

    -- Ensure the file ends with a trailing newline if it has content
    if #content > 0 and content:sub(-1) ~= "\n" then
        local file = io.open(SCRIPT_LOG__PATH, "a")
        if file then
            file:write("\n")
            file:close()
        end
    end
end

local function write_to_log_file(player_entries_to_log)
    local log_file, err = io.open(SCRIPT_LOG__PATH, "a")
    if err then
        create_empty_file(SCRIPT_LOG__PATH)
        log_file, err = io.open(SCRIPT_LOG__PATH, "a")
        if err then
            handle_script_exit({ hasScriptCrashed = true })
            return
        end
    end

    log_file:write(table.concat(player_entries_to_log, "\n") .. "\n")
    log_file:close()
end


-- === Main Menu Features ===
FeatureMgr.AddFeature(FEATURE_SESSION_SNIFFER_LOGGING_HASH, "Toggle Session Sniffer Logging", eFeatureType.Toggle, "Toggle Session Sniffer Logging")

ClickGUI.AddTab(SCRIPT_TITLE, function()
    if ClickGUI.BeginCustomChildWindow("Session Sniffer Logging") then
        ClickGUI.RenderFeature(FEATURE_SESSION_SNIFFER_LOGGING_HASH)
        ClickGUI.EndCustomChildWindow()
    end
end)


-- === Initialization ===
init_log_cache()


-- === Main Loop ===
mainLoopThread = Script.RegisterLooped(function()
    if FeatureMgr.IsFeatureToggled(FEATURE_SESSION_SNIFFER_LOGGING_HASH) then
        local currentTimestamp = Time.GetEpoche()

        if currentTimestamp - last_logger_scan_timestamp >= LOGGER_SCAN_INTERVAL_SECONDS then
            last_logger_scan_timestamp = currentTimestamp

            -- Only scan if in an active online session; zero disk/CPU cost otherwise
            if Natives.InvokeBool(NATIVE_NETWORK_IS_SESSION_STARTED) then
                local player_entries_to_log = {}

                for _, playerID in pairs(Players.Get()) do
                    local CNetGamePlayer = Players.GetById(playerID)
                    if CNetGamePlayer then
                        local GamerInfo = CNetGamePlayer:GetGamerInfo()
                        if GamerInfo and GamerInfo.RockstarId then
                            local playerSCID = GamerInfo.RockstarId
                            local playerName = Players.GetName(playerID)
                            local playerIPString = Players.GetIPString(playerID)

                            if playerIPString then
                                local playerIP = playerIPString:match("^(%d+%.%d+%.%d+%.%d+) %(Direct%)")
                                if (
                                    playerIP
                                    and playerIP ~= "255.255.255.255"
                                    and playerIP ~= "0.0.0.0"
                                    and playerName
                                    and playerName ~= ""
                                ) then
                                    local key = make_dedup_key(playerSCID, playerIP, playerName)
                                    if not logged_players[key] then
                                        logged_players[key] = true
                                        player_entries_to_log[#player_entries_to_log + 1] = string.format(
                                            "user:%s, scid:%d, ip:%s, timestamp:%d",
                                            playerName, playerSCID, playerIP, currentTimestamp
                                        )
                                    end
                                end
                            end
                        end
                    end
                end

                if #player_entries_to_log > 0 then
                    write_to_log_file(player_entries_to_log)
                end
            end
        end
    else
        last_logger_scan_timestamp = 0
    end

    Script.Yield()
end)
