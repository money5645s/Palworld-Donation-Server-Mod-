ModActor = nil
PalUtility = nil
World = nil
pendingDonations = {}

scriptSource = debug.getinfo(1, "S").source or ""
scriptPath = scriptSource:sub(1, 1) == "@" and scriptSource:sub(2) or scriptSource
scriptDirectory = scriptPath:match("^(.*)[/\\\\]") or "."
donationQueuePath = DonationConfig.paths.donationQueue
playerStatusPath = DonationConfig.paths.playerStatus
streamerRegistrationRequestPath = DonationConfig.paths.streamerRegistrationRequest
streamerRegistrationResponsePath = DonationConfig.paths.streamerRegistrationResponse
bindingDumpRequestPath = DonationConfig.paths.bindingDumpRequest
donationQueueOffset = nil
streamerRegistrationResponseOffset = nil
playerStatusPollCount = 0
streamerRegistrationSequence = 0

-- Seed the random generator
math.randomseed(os.time())

local serverTerminalOutput = nil
local serverTerminalChecked = false

local function writeToServerTerminal(line)
    -- UE4SS print() writes to its debug console/log.  Dedicated-server users
    -- normally watch the Windows terminal instead, so open its CONOUT$ device
    -- once and mirror each DonationMod line there as well.
    if not serverTerminalChecked then
        serverTerminalChecked = true
        local openOk, outputOrErr = pcall(function()
            return io.open("CONOUT$", "w")
        end)
        if openOk and outputOrErr ~= nil then
            serverTerminalOutput = outputOrErr
        end
    end

    local terminalOk = false
    if serverTerminalOutput ~= nil then
        terminalOk = pcall(function()
            serverTerminalOutput:write(line .. "\r\n")
            serverTerminalOutput:flush()
        end)
    end

    -- Some server launchers redirect CONOUT$ but preserve stdout.  Try that
    -- only when the direct console device was unavailable.
    if not terminalOk and io ~= nil and io.stdout ~= nil then
        pcall(function()
            io.stdout:write(line .. "\r\n")
            io.stdout:flush()
        end)
    end
end

function log(message)
    local line = string.format("[DonationMod] %s", tostring(message))
    print(line .. "\n")
    writeToServerTerminal(line)
end

log("터미널 로그 미러를 활성화했습니다.")

function translateGuid(Userdata)
    local self = {}
    self.A = Userdata.A
    self.B = Userdata.B
    self.C = Userdata.C
    self.D = Userdata.D
    return self
end

function ensureGameReferences()
    if PalUtility == nil or not PalUtility:IsValid() then
        PalUtility = StaticFindObject("/Script/Pal.Default__PalUtility")
    end
    if World == nil or not World:IsValid() then
        World = FindFirstOf("World")
    end
    return PalUtility ~= nil and PalUtility:IsValid() and World ~= nil and World:IsValid()
end

function findPlayerStateByUid(playerUid)
    local players = FindAllOf("PalPlayerController") or {}
    for _, player in pairs(players) do
        local playerState = player:GetPalPlayerState()
        if playerState ~= nil and playerState:IsValid() and playerState.PlayerUId.A == playerUid.A then
            return playerState, player
        end
    end
    return nil, nil
end

local function giveItemToPlayerUnchecked(playerUid, itemId, count)
    if not ensureGameReferences() then
        log("아이템 지급에 필요한 게임 참조를 찾지 못했습니다.")
        return false
    end

    local _, playerController = findPlayerStateByUid(playerUid)
    if playerController == nil or not playerController:IsValid() then
        log("아이템 지급 대상 플레이어를 찾지 못했습니다.")
        return false
    end

    local pawn = playerController.Pawn
    if pawn == nil or not pawn:IsValid() then
        log("아이템 지급 대상 캐릭터를 찾지 못했습니다.")
        return false
    end

    local playerState = PalUtility:GetPlayerState(pawn)
    if playerState == nil or not playerState:IsValid() then
        log("아이템을 지급할 대상 플레이어를 찾을 수 없습니다.")
        return false
    end

    local inventory = playerState:GetInventoryData()
    if inventory == nil or not inventory:IsValid() then
        log("대상 플레이어의 인벤토리에 접근할 수 없습니다.")
        return false
    end

    local nameOk, itemNameOrErr = pcall(function()
        return FName(itemId)
    end)
    if not nameOk then
        log("아이템 ID를 FName으로 변환하는 데 실패했습니다 (" .. tostring(itemId) .. "): " .. tostring(itemNameOrErr))
        return false
    end

    -- 이 서버의 구형 UE4SS/Palworld 조합은 StaticItemId, Count,
    -- IsAssignPassive, LogDelay 순서의 인자 4개를 사용합니다.
    -- A reflected UFunction must be invoked with its target UObject context.
    -- UE4SS 3.x does not expose UObject:CallFunction, so pass the inventory
    -- UObject as the first argument to the reflected UFunction instead.
    local ok, resultOrErr = pcall(function()
        -- The reflected function has six fields, but the last one is its enum
        -- return value.  UE4SS accepts only the five input fields here.
        return inventory:AddItem_ServerInternal(itemNameOrErr, count, false, 0.0, false)
    end)
    if not ok then
        log("아이템 지급에 실패했습니다: " .. tostring(resultOrErr))
        return false
    end
    log(string.format("아이템 지급 완료: %s x%d (결과: %s)", itemId, count, tostring(resultOrErr)))
    return resultOrErr ~= false
end

-- 인벤토리 데이터가 안정된 다음 게임 틱에 지급합니다.
-- 후원 채팅 훅의 같은 틱에 접근하면 UE4SS가 내부 인벤토리 호출을 거부할 수 있습니다.
local function normalizeItemId(itemId)
    if type(itemId) == "string" then
        local trimmed = itemId:match("^%s*(.-)%s*$")
        if trimmed ~= "" then
            return trimmed
        end
        return nil, "item ID is empty"
    end

    local converted, itemNameOrErr = pcall(function()
        return itemId:ToString()
    end)
    if not converted or type(itemNameOrErr) ~= "string" then
        return nil, "item ID cannot be converted to text: " .. tostring(itemNameOrErr)
    end
    return normalizeItemId(itemNameOrErr)
end

local function normalizeItemCount(count)
    local normalized = tonumber(count)
    if normalized == nil or normalized < 1 or normalized % 1 ~= 0 then
        return nil
    end
    return normalized
end

function giveItemToPlayer(playerUid, itemId, count)
    local normalizedItemId, itemIdErr = normalizeItemId(itemId)
    if normalizedItemId == nil then
        log("Item delivery failed: " .. itemIdErr)
        return false
    end

    local normalizedCount = normalizeItemCount(count)
    if normalizedCount == nil then
        log("Item delivery failed: invalid count for " .. normalizedItemId .. " (" .. tostring(count) .. ")")
        return false
    end

    local delivered = giveItemToPlayerUnchecked(playerUid, normalizedItemId, normalizedCount)
    if not delivered then
        log("Item delivery failed: " .. normalizedItemId .. " x" .. normalizedCount)
    end
    return delivered
end

function queueItemDelivery(playerUid, itemId, count, onComplete)
    ExecuteWithDelay(0, function()
        local delivered = giveItemToPlayer(playerUid, itemId, count)
        if onComplete ~= nil then
            onComplete(delivered)
        end
    end)
end

function broadcastToPlayers(message)
    if not ensureGameReferences() then
        log("서버 월드가 준비되지 않아 전체 안내를 전송할 수 없습니다.")
        return false
    end

    local delivered = false
    local players = FindAllOf("PalPlayerController") or {}
    for _, player in pairs(players) do
        local playerState = player:GetPalPlayerState()
        if playerState ~= nil and playerState:IsValid() then
            local ok, err = pcall(function()
                PalUtility:SendSystemToPlayerChat(World, message, translateGuid(playerState.PlayerUId))
            end)
            if not ok then
                log("전체 안내 전송에 실패했습니다: " .. tostring(err))
            else
                delivered = true
            end
        end
    end
    return delivered
end

function sendSystemToPlayer(playerUid, message)
    if not ensureGameReferences() then
        return false
    end

    local ok, err = pcall(function()
        PalUtility:SendSystemToPlayerChat(World, message, playerUid)
    end)
    if not ok then
        log("시스템 채팅 전송에 실패했습니다: " .. tostring(err))
        return false
    end
    return true
end

function queueStreamerRegistrationRequest(action, playerUid, playerName, channelInput)
    streamerRegistrationSequence = streamerRegistrationSequence + 1
    local requestId = string.format("streamer-%d-%d-%d", os.time(), playerUid.A, streamerRegistrationSequence)
    local safeName = tostring(playerName or ""):gsub("[\t\r\n]", " ")
    local safeInput = tostring(channelInput or ""):gsub("[\t\r\n]", " ")
    local requestFile = io.open(streamerRegistrationRequestPath, "a")
    if requestFile == nil then
        return nil, "스트리머 등록 요청 파일을 쓸 수 없습니다."
    end

    requestFile:write(requestId, "\t", action, "\t", tostring(playerUid.A), "\t", safeName, "\t", safeInput, "\n")
    requestFile:close()
    return requestId, nil
end

DirectDonationActor = {}

function DirectDonationActor:IsValid()
    return true
end

function DirectDonationActor:GiveItem(playerUid, itemId, count)
    local itemName = itemId
    if type(itemId) ~= "string" then
        local ok, value = pcall(function()
            return itemId:ToString()
        end)
        if not ok then
            log("지급할 아이템 이름을 변환할 수 없습니다.")
            return false
        end
        itemName = value
    end
    return giveItemToPlayer(playerUid, itemName, count)
end

function DirectDonationActor:Broadcast(message)
    return broadcastToPlayers(message)
end

-- The original project expects a Blueprint actor.  This proxy keeps its
-- existing reward rules working while routing them through server-side Lua.
ModActor = DirectDonationActor

function findPlayer(Id)
    local result = PalUtility:GetPlayerUIdByString(World, Id);
    if result ~= nil and result.A ~= 0 then
        return result
    end
    local Players = FindAllOf("PalPlayerController")
    for _, player in pairs(Players) do
        local playerState = player:GetPalPlayerState()
        if playerState ~= nil and playerState:IsValid() then
            local uid = string.lower(string.sub(string.format("%016x", playerState.PlayerUId.A), -8))
            if string.lower(Id) == uid or string.lower(Id) == (uid .. "000000000000000000000000") then
                return playerState.PlayerUId
            end
            if string.lower(Id) == string.lower(playerState.PlayerNamePrivate:ToString()) then
                return playerState.PlayerUId
            end
        end
    end
    return nil
end

-- 1. 소모품 룰렛 아이템 선택
