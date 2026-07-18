local function dumpCombatFunctions(label, object)
    if object == nil or not object:IsValid() then
        log(label .. "을(를) 사용할 수 없습니다.")
        return
    end

    local class = object:GetClass()
    class:ForEachFunction(function(func)
        local name = func:GetFName():ToString()
        local lowerName = name:lower()
        if lowerName:find("die", 1, true)
            or lowerName:find("death", 1, true)
            or lowerName:find("kill", 1, true)
            or lowerName:find("damage", 1, true)
            or lowerName:find("health", 1, true)
            or lowerName:find("hp", 1, true) then
            log(label .. " 후보 함수: " .. name)
        end
    end)
end

local donationChatCommandHookOk, donationChatCommandHookErr = pcall(function()
    RegisterHook("/Script/Pal.PalGameStateInGame:BroadcastChatMessage", function(_, ChatMessage)
        local chat = ChatMessage:get()
        local message = chat.Message:ToString()
        local command, value = message:match("^!(%S+)%s*(.*)$")
        local normalizedCommand = command and command:lower()
        if normalizedCommand ~= "done"
            and normalizedCommand ~= "donationtest"
            and normalizedCommand ~= "donationdebug"
            and normalizedCommand ~= "chzzkregister"
            and normalizedCommand ~= "chzzkstatus"
            and normalizedCommand ~= "chzzkunregister" then
            return
        end

        local playerUid = translateGuid(chat.SenderPlayerUId)
        local playerState = findPlayerStateByUid(playerUid)
        if playerState == nil then
            log("후원 명령을 거부했습니다: 입력한 플레이어를 확인할 수 없습니다.")
            return
        end

        if normalizedCommand == "chzzkregister"
            or normalizedCommand == "chzzkstatus"
            or normalizedCommand == "chzzkunregister" then
            local action = normalizedCommand == "chzzkregister" and "register"
                or (normalizedCommand == "chzzkstatus" and "status" or "unregister")
            local playerName = playerState.PlayerNamePrivate:ToString()
            local requestId, requestErr = queueStreamerRegistrationRequest(action, playerUid, playerName, value)
            if requestId == nil then
                log("CHZZK 등록 요청에 실패했습니다: " .. tostring(requestErr))
                sendSystemToPlayer(playerUid, "[CHZZK] 채널 리스너에 연결할 수 없습니다. 리스너 창을 확인하세요.")
            elseif action == "register" then
                sendSystemToPlayer(playerUid, "[CHZZK] 채널 등록을 요청했습니다. 연결 결과를 채팅에서 확인하세요.")
            elseif action == "status" then
                sendSystemToPlayer(playerUid, "[CHZZK] 채널 연결 상태를 확인하고 있습니다...")
            else
                sendSystemToPlayer(playerUid, "[CHZZK] 채널 연결을 해제하고 있습니다...")
            end
            return
        end

        local playerController = playerState:GetPlayerController()
        if playerController == nil or not playerController.bAdmin then
            sendSystemToPlayer(playerUid, "[후원] 테스트 명령은 관리자만 사용할 수 있습니다.")
            log("후원 테스트를 거부했습니다: 관리자 권한이 없습니다.")
            return
        end

        if normalizedCommand == "donationdebug" then
            local pawn = playerController.Pawn
            dumpCombatFunctions("Pawn", pawn)
            if pawn ~= nil and pawn:IsValid() then
                dumpCombatFunctions("CharacterParameterComponent", pawn.CharacterParameterComponent)
            end
            log("전투 관련 함수 목록 추출이 완료되었습니다. UE4SS.log에서 DonationMod 후보를 확인하세요.")
            return
        end

        -- Supported forms:
        --   !done 10000                 (the admin running the command)
        --   !done PlayerName 10000      (a named online player)
        -- The amount is parsed from the final token so player names may
        -- contain spaces.  Quoted names are also accepted.
        local targetPlayerUid = playerUid
        local targetSelector, amountText = value:match("^(.-)%s+(%d+)%s*$")
        local amount = nil

        if targetSelector ~= nil then
            targetSelector = targetSelector:match("^%s*(.-)%s*$")
            if targetSelector == "" then
                amount = tonumber(amountText)
            else
                local firstCharacter = targetSelector:sub(1, 1)
                local lastCharacter = targetSelector:sub(-1)
                if #targetSelector >= 2
                    and ((firstCharacter == "\"" and lastCharacter == "\"")
                        or (firstCharacter == "'" and lastCharacter == "'")) then
                    targetSelector = targetSelector:sub(2, -2)
                end

                targetPlayerUid = findPlayer(targetSelector)
                if targetPlayerUid == nil then
                    sendSystemToPlayer(playerUid, "[후원] 대상 플레이어를 찾지 못했습니다: " .. targetSelector)
                    log("후원 테스트 명령 거부: 대상 플레이어를 찾지 못했습니다: " .. targetSelector)
                    return
                end
                amount = tonumber(amountText)
            end
        else
            amount = tonumber(value)
        end

        if amount ~= DonationConfig.amounts.skyTeleport
            and amount ~= DonationConfig.amounts.dropPal
            and amount ~= DonationConfig.amounts.consumableRoulette
            and amount ~= DonationConfig.amounts.randomItemRemoval then
            sendSystemToPlayer(playerUid, "[후원] 테스트 금액은 1000, 5000, 7000, 10000만 사용할 수 있습니다.")
            log("후원 테스트를 거부했습니다: 지원 금액은 modules/config.lua에 설정된 값만 사용할 수 있습니다.")
            return
        end

        log(string.format("[후원] 테스트 명령 수락: !%s %d", normalizedCommand, amount))
        sendSystemToPlayer(playerUid, string.format("[후원] 테스트 보상을 처리합니다: %d원", amount))

        do
            local ok, err = pcall(handleDonationRule, targetPlayerUid, amount)
            if not ok then
                sendSystemToPlayer(playerUid, "[후원] 테스트 처리 중 오류가 발생했습니다. 서버 로그를 확인하세요.")
                log("후원 테스트에 실패했습니다: " .. tostring(err))
            end
        end
    end)
end)

if not donationChatCommandHookOk then
    log("후원 채팅 명령 훅을 사용할 수 없습니다: " .. tostring(donationChatCommandHookErr))
end
