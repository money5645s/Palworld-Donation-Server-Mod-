-- Filesystem polling runs in LoopAsync.  It must never access Unreal Engine
-- objects directly because that work may run while a player is loading.

-- The listener can resend an event when it sees the queue file before the
-- acknowledgement write completes.  Claim each event ID before scheduling it
-- so one donation can produce at most one broadcast and one reward action.
local recentDonationEventIds = {}
local recentDonationEventOrder = {}
local maxRecentDonationEventIds = 4096

local function claimDonationEvent(eventId)
    if recentDonationEventIds[eventId] then
        return false
    end

    recentDonationEventIds[eventId] = true
    table.insert(recentDonationEventOrder, eventId)

    if #recentDonationEventOrder > maxRecentDonationEventIds then
        local expiredEventId = table.remove(recentDonationEventOrder, 1)
        recentDonationEventIds[expiredEventId] = nil
    end
    return true
end

function processDonation(playerId, amount, eventId)
    local playerUid = { A = playerId, B = 0, C = 0, D = 0 }
    if not ensureGameReferences() then
        table.insert(pendingDonations, { playerId = playerId, amount = amount, eventId = eventId })
        log("서버 월드가 준비될 때까지 후원을 대기열에 보관합니다: " .. eventId)
        return
    end

    local ok, err = pcall(handleDonationRule, playerUid, amount)
    if not ok then
        log("후원 처리에 실패했습니다 (" .. eventId .. "): " .. tostring(err))
    end
end

function dispatchDonation(playerId, amount, eventId)
    if not claimDonationEvent(eventId) then
        log("duplicate donation event ignored: " .. eventId)
        return
    end

    ExecuteInGameThread(function()
        processDonation(playerId, amount, eventId)
    end)
end

function flushPendingDonations()
    local queuedDonations = pendingDonations
    pendingDonations = {}

    for _, donation in ipairs(queuedDonations) do
        processDonation(donation.playerId, donation.amount, donation.eventId)
    end
end

function writePlayerStatus()
    local statusFile = io.open(playerStatusPath, "w")
    if statusFile == nil then
        return
    end

    local players = FindAllOf("PalPlayerController") or {}
    for _, player in pairs(players) do
        local playerState = player:GetPalPlayerState()
        if playerState ~= nil and playerState:IsValid() then
            local name = playerState.PlayerNamePrivate:ToString():gsub("[\t\r\n]", " ")
            statusFile:write(tostring(playerState.PlayerUId.A), "\t", name, "\n")
        end
    end
    statusFile:close()
end

-- Remove only the bytes that were already read.  Re-reading immediately
-- before rewriting preserves any new event appended while this poll ran.
local function removeConsumedDonationQueueBytes(consumedBytes)
    if consumedBytes == nil or consumedBytes <= 0 then
        return true
    end

    local latestQueueFile = io.open(donationQueuePath, "r")
    if latestQueueFile == nil then
        return false, "queue read failed while acknowledging events"
    end
    local latestContents = latestQueueFile:read("*a") or ""
    latestQueueFile:close()

    local remainingContents = latestContents:sub(consumedBytes + 1)
    local replacementFile = io.open(donationQueuePath, "w")
    if replacementFile == nil then
        return false, "queue clear failed"
    end
    replacementFile:write(remainingContents)
    replacementFile:close()
    return true
end

function pollDonationQueue()
    local queueFile = io.open(donationQueuePath, "r")
    if queueFile == nil then
        return
    end

    if donationQueueOffset == nil then
        local staleQueueLength = queueFile:seek("end") or 0
        donationQueueOffset = 0
        queueFile:close()
        if staleQueueLength > 0 then
            local cleared, clearErr = removeConsumedDonationQueueBytes(staleQueueLength)
            if not cleared then
                log("donation queue startup clear failed: " .. tostring(clearErr))
            end
        end
        log("후원 이벤트 대기열 감지를 시작했습니다: " .. donationQueuePath)
        return
    end

    local queueLength = queueFile:seek("end") or 0
    if donationQueueOffset > queueLength then
        donationQueueOffset = 0
    end
    queueFile:seek("set", donationQueueOffset)

    while true do
        local line = queueFile:read("*l")
        if line == nil then
            break
        end
        donationQueueOffset = queueFile:seek()

        local eventId, playerId, amount = line:match("^([^\t]+)\t(-?%d+)\t(%d+)$")
        playerId = tonumber(playerId)
        amount = tonumber(amount)
        if eventId ~= nil and playerId ~= nil and amount ~= nil then
            dispatchDonation(playerId, amount, eventId)
        else
            log("형식이 올바르지 않은 후원 대기열 항목을 무시했습니다.")
        end
    end

    queueFile:close()

    if donationQueueOffset > 0 then
        local cleared, clearErr = removeConsumedDonationQueueBytes(donationQueueOffset)
        if cleared then
            donationQueueOffset = 0
        else
            log("donation queue acknowledge failed: " .. tostring(clearErr))
        end
    end
end

function pollStreamerRegistrationResponses()
    local responseFile = io.open(streamerRegistrationResponsePath, "r")
    if responseFile == nil then
        return
    end

    if streamerRegistrationResponseOffset == nil then
        streamerRegistrationResponseOffset = responseFile:seek("end") or 0
        responseFile:close()
        log("스트리머 등록 응답 감지를 시작했습니다: " .. streamerRegistrationResponsePath)
        return
    end

    local responseLength = responseFile:seek("end") or 0
    if streamerRegistrationResponseOffset > responseLength then
        streamerRegistrationResponseOffset = 0
    end
    responseFile:seek("set", streamerRegistrationResponseOffset)

    local pendingResponses = {}
    while true do
        local line = responseFile:read("*l")
        if line == nil then
            break
        end
        streamerRegistrationResponseOffset = responseFile:seek()

        local requestId, rawPlayerId, status, responseMessage = line:match("^([^\t]+)\t(-?%d+)\t([^\t]+)\t(.*)$")
        local playerId = tonumber(rawPlayerId)
        if requestId ~= nil and playerId ~= nil and status ~= nil then
            table.insert(pendingResponses, {
                playerId = playerId,
                status = status,
                message = responseMessage,
            })
        else
            log("형식이 올바르지 않은 스트리머 등록 응답을 무시했습니다.")
        end
    end

    responseFile:close()

    if #pendingResponses > 0 then
        ExecuteInGameThread(function()
            for _, response in ipairs(pendingResponses) do
                local playerUid = { A = response.playerId, B = 0, C = 0, D = 0 }
                sendSystemToPlayer(playerUid, "[CHZZK] " .. response.message)
                log("스트리머 등록 응답 (" .. response.status .. ", UID.A=" .. tostring(response.playerId) .. "): " .. response.message)
            end
        end)
    end
end

LoopAsync(250, function()
    local ok, err = pcall(pollDonationQueue)
    if not ok then
        log("후원 대기열 읽기에 실패했습니다: " .. tostring(err))
    end

    local registrationOk, registrationErr = pcall(pollStreamerRegistrationResponses)
    if not registrationOk then
        log("스트리머 등록 응답 읽기에 실패했습니다: " .. tostring(registrationErr))
    end

    playerStatusPollCount = playerStatusPollCount + 1
    if playerStatusPollCount >= 20 then
        playerStatusPollCount = 0
        ExecuteInGameThread(function()
            local statusOk, statusErr = pcall(writePlayerStatus)
            if not statusOk then
                log("플레이어 상태 파일 작성에 실패했습니다: " .. tostring(statusErr))
            end
        end)
    end

    if #pendingDonations > 0 then
        ExecuteInGameThread(flushPendingDonations)
    end
    return false
end)
