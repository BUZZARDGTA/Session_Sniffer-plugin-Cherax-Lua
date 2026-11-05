-- Author: IB_U_Z_Z_A_R_Dl
-- Description: Plugin for Session Sniffer project on GitHub.
-- Allows you to automatically have every usernames and the session host showing up on Session Sniffer project, by logging all players from your sessions to "Cherax\Lua\Session_Sniffer-plugin\log.txt" and tracking the session host in "Cherax\Lua\Session_Sniffer-plugin\session_host.txt".
-- GitHub Repository: https://github.com/BUZZARDGTA/Session_Sniffer-plugin-Cherax-Lua


-- === Globals ===
local mainLoopThread = nil
local last_player_scan_timestamp = 0
local logged_players = {}
local last_written_host_key = nil

-- === Constants ===
local SCRIPT_NAME <const> = "Session_Sniffer-plugin.lua"
local SCRIPT_TITLE <const> = "Session Sniffer"
local SCRIPT_LOG__PATH <const> = FileMgr.GetMenuRootPath() .. "\\Lua\\Session_Sniffer-plugin\\log.txt"
local SCRIPT_HOST__PATH <const> = FileMgr.GetMenuRootPath() .. "\\Lua\\Session_Sniffer-plugin\\session_host.txt"
local PLAYER_SCAN_INTERVAL_SECONDS <const> = 1
local NATIVE_NETWORK_IS_SESSION_STARTED <const> = 0x9DE624D2FC4B603F
local FEATURE_LOG_SESSION_PLAYERS_HASH <const> = Utils.Joaat("SessionSnifferLogPlayers")
local FEATURE_TRACK_SESSION_HOST_HASH <const> = Utils.Joaat("SessionSnifferTrackHost")

-- === Utility Functions ===
local function handle_script_exit(params)
    params = params or {}
    FileMgr.WriteFileContent(SCRIPT_HOST__PATH, "", false)
    if params.hasScriptCrashed then
        GUI.AddToast(SCRIPT_TITLE, "Oh no... Script crashed:(\nYou gotta restart it manually.", 10000, eToastPos.BOTTOM_RIGHT)
    end

    SetShouldUnload()
end

local function make_dedup_key(scid, ip, name)
    return scid .. ":" .. ip .. ":" .. name
end

local function write_session_host_file(host_key, host_entry)
    host_key = host_key or ""
    host_entry = host_entry or ""
    if host_key == last_written_host_key then
        return
    end

    if not FileMgr.WriteFileContent(SCRIPT_HOST__PATH, host_entry, false) then
        handle_script_exit({ hasScriptCrashed = true })
        return
    end

    last_written_host_key = host_key
end

local function init_log_cache()
    local dir = SCRIPT_LOG__PATH:match("^(.*)[/\\]")
    if dir and not FileMgr.DoesFileExist(dir) then
        FileMgr.CreateDir(dir)
    end

    write_session_host_file("", "")

    if not FileMgr.DoesFileExist(SCRIPT_LOG__PATH) then
        FileMgr.WriteFileContent(SCRIPT_LOG__PATH, "", false)
        GUI.AddToast(SCRIPT_TITLE, "Initialized new log file.", 5000, eToastPos.BOTTOM_RIGHT)
        return
    end

    local content = FileMgr.ReadFileContent(SCRIPT_LOG__PATH)
    if not content or #content == 0 then
        return
    end

    local loaded_count = 0
    for line in content:gmatch("[^\r\n]+") do
        local name, scid, ip = line:match("^user:(.-), scid:(%d+), ip:([%d%.]+)")
        if name and scid and ip then
            local key = make_dedup_key(scid, ip, name)
            if not logged_players[key] then
                logged_players[key] = true
                loaded_count = loaded_count + 1
            end
        end
    end

    -- Ensure the file ends with a trailing newline if it has content
    if content:sub(-1) ~= "\n" then
        FileMgr.WriteFileContent(SCRIPT_LOG__PATH, "\n", true)
    end

    GUI.AddToast(
        SCRIPT_TITLE,
        string.format("Loaded %d unique player%s from log.", loaded_count, loaded_count == 1 and "" or "s"),
        5000,
        eToastPos.BOTTOM_RIGHT
    )
end

local function write_to_log_file(player_entries_to_log)
    local combined_entries = table.concat(player_entries_to_log, "\n") .. "\n"
    if not FileMgr.WriteFileContent(SCRIPT_LOG__PATH, combined_entries, true) then
        handle_script_exit({ hasScriptCrashed = true })
    end
end


-- === Main Menu Features ===
FeatureMgr.AddFeature(
    FEATURE_LOG_SESSION_PLAYERS_HASH,
    "Log Session Players",
    eFeatureType.Toggle,
    "Logs all players from your sessions to log.txt for Session Sniffer."
):SetDefaultValue(true):Toggle(true)

FeatureMgr.AddFeature(
    FEATURE_TRACK_SESSION_HOST_HASH,
    "Track Session Host",
    eFeatureType.Toggle,
    "Tracks the current session host in session_host.txt for Session Sniffer."
):SetDefaultValue(true):Toggle(true)

ClickGUI.AddTab(SCRIPT_TITLE, function()
    if ClickGUI.BeginCustomChildWindow("Session Sniffer Plugin") then
        ClickGUI.RenderFeature(FEATURE_LOG_SESSION_PLAYERS_HASH)
        ClickGUI.RenderFeature(FEATURE_TRACK_SESSION_HOST_HASH)
        ClickGUI.EndCustomChildWindow()
    end
end)


-- === Initialization ===
init_log_cache()

EventMgr.RegisterHandler(eLuaEvent.ON_UNLOAD, function()
    FileMgr.WriteFileContent(SCRIPT_HOST__PATH, "", false)
end)


-- === Main Loop ===
mainLoopThread = Script.RegisterLooped(function()
    if ShouldUnload() then
        return
    end

    local logPlayersEnabled = FeatureMgr.IsFeatureToggled(FEATURE_LOG_SESSION_PLAYERS_HASH)
    local trackHostEnabled = FeatureMgr.IsFeatureToggled(FEATURE_TRACK_SESSION_HOST_HASH)

    if not trackHostEnabled then
        write_session_host_file("", "")
    end

    if logPlayersEnabled or trackHostEnabled then
        local currentTimestamp = Time.GetEpoche()

        if currentTimestamp - last_player_scan_timestamp >= PLAYER_SCAN_INTERVAL_SECONDS then
            last_player_scan_timestamp = currentTimestamp

            if Natives.InvokeBool(NATIVE_NETWORK_IS_SESSION_STARTED) then
                local player_entries_to_log = nil
                local host_key = ""
                local host_entry = ""
                local hostPlayerID = nil
                if trackHostEnabled then
                    local hostQueue = Players.Get(ePlayerListSort.HOST_QUEUE)
                    hostPlayerID = hostQueue and hostQueue[1]
                end

                for _, playerID in ipairs(Players.Get()) do
                    local CNetGamePlayer = Players.GetById(playerID)
                    if CNetGamePlayer and not CNetGamePlayer:IsLocalPlayer() then
                        local GamerInfo = CNetGamePlayer:GetGamerInfo()
                        local playerSCID = GamerInfo and GamerInfo.RockstarId

                        if playerSCID and playerSCID > 0 then
                            local playerIPString = Players.GetIPString(playerID)
                            if playerIPString then
                                local playerIP = playerIPString:match("^(%d+%.%d+%.%d+%.%d+) %(Direct%)")
                                if playerIP and playerIP ~= "255.255.255.255" and playerIP ~= "0.0.0.0" then
                                    local playerName = CNetGamePlayer:GetName()
                                    if playerName and playerName ~= "" and playerName ~= "**Invalid**" then
                                        local key = make_dedup_key(playerSCID, playerIP, playerName)
                                        local formatted_entry = string.format(
                                            "user:%s, scid:%d, ip:%s, timestamp:%d",
                                            playerName, playerSCID, playerIP, currentTimestamp
                                        )
                                        if logPlayersEnabled and not logged_players[key] then
                                            logged_players[key] = true
                                            player_entries_to_log = player_entries_to_log or {}
                                            player_entries_to_log[#player_entries_to_log + 1] = formatted_entry
                                        end
                                        if trackHostEnabled and playerID == hostPlayerID then
                                            host_key = key
                                            host_entry = formatted_entry .. "\n"
                                        end
                                    end
                                end
                            end
                        end
                    end
                end

                if logPlayersEnabled and player_entries_to_log then
                    write_to_log_file(player_entries_to_log)
                end

                if trackHostEnabled then
                    write_session_host_file(host_key, host_entry)
                end
            elseif trackHostEnabled then
                write_session_host_file("", "")
            end
        end
    end

    Script.Yield()
end)
