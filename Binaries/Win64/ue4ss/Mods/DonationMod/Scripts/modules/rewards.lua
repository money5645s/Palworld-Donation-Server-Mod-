local function findPlayerName(playerUid)
    local players = FindAllOf("PalPlayerController") or {}
    for _, player in pairs(players) do
        local playerState = player:GetPalPlayerState()
        if playerState ~= nil and playerState:IsValid() and playerState.PlayerUId.A == playerUid.A then
            return playerState.PlayerNamePrivate:ToString()
        end
    end
    return "플레이어"
end

-- 5천원: 파티에서 무작위 팰 하나를 게임 내 드롭 처리로 버립니다.
-- 게임이 네트워크 동기화를 끝내기 전 같은 슬롯을 다시 고르는 일을 막습니다.
local pendingPalDropSlots = {}

local function getPalName(handle)
    local parameterOk, parameter = pcall(function()
        return handle:TryGetIndividualParameter()
    end)
    if not parameterOk or parameter == nil or not parameter:IsValid() then
        return "알 수 없는 팰"
    end

    local idOk, characterId = pcall(function()
        return parameter:GetCharacterID()
    end)
    if idOk and characterId ~= nil then
        local nameOk, name = pcall(function()
            return characterId:ToString()
        end)
        if nameOk and name ~= nil and name ~= "" then
            return name
        end
    end
    return "알 수 없는 팰"
end

local function makePalDropSlotKey(playerUid, slotIndex)
    return tostring(playerUid.A) .. ":" .. tostring(slotIndex)
end

local function isSelectedHandleStillInSlot(holder, slotIndex, selectedHandle)
    local handleOk, currentHandle = pcall(function()
        return holder:GetOtomoIndividualHandle(slotIndex)
    end)
    if not handleOk or currentHandle == nil then
        return false
    end

    local validOk, isValid = pcall(function()
        return currentHandle:IsValid()
    end)
    return validOk and isValid and currentHandle == selectedHandle
end

function dropRandomPartyPal(playerUid, onComplete)
    local playerState, playerController = findPlayerStateByUid(playerUid)
    if playerState == nil or playerController == nil then
        return false
    end

    local holder = playerController.BP_OtomoPalHolderComponent
    if holder == nil or not holder:IsValid() then
        log("팰 드롭 실패: 파티 팰 홀더를 찾지 못했습니다.")
        return false
    end

    local countOk, partyCount = pcall(function()
        return holder:GetOtomoCount()
    end)
    if not countOk or type(partyCount) ~= "number" or partyCount < 1 then
        log("팰 드롭 실패: 보유한 파티 팰이 없습니다.")
        return false
    end

    -- GetOtomoCount reports how many Pals are assigned, not the highest
    -- occupied party-slot index.  A party can have gaps, so inspect all five
    -- actual party slots instead of only 0..(count - 1).
    local occupiedSlots = {}
    local partySlotCount = 5
    for slotIndex = 0, partySlotCount - 1 do
        local handleOk, handle = pcall(function()
            return holder:GetOtomoIndividualHandle(slotIndex)
        end)
        local slotKey = makePalDropSlotKey(playerUid, slotIndex)
        if handleOk and handle ~= nil and not pendingPalDropSlots[slotKey] then
            local validOk, isValid = pcall(function()
                return handle:IsValid()
            end)
            if validOk and isValid then
                table.insert(occupiedSlots, {
                    index = slotIndex,
                    handle = handle,
                })
            end
        end
    end

    -- Keep one Pal in the party.  Besides being less punishing, this avoids
    -- the game's server RPC refusing a drop when it would empty the party.
    if #occupiedSlots < 2 then
        log("팰 드롭 실패: 마지막 한 마리는 보호됩니다.")
        log("팰 드롭 실패: 드롭 가능한 파티 팰을 찾지 못했습니다.")
        return false
    end

    local selected = occupiedSlots[math.random(1, #occupiedSlots)]
    local transmitter = playerController.Transmitter
    local networkPlayer = transmitter ~= nil and transmitter.Player or nil
    if networkPlayer == nil or not networkPlayer:IsValid() then
        log("팰 드롭 실패: 네트워크 플레이어 컴포넌트를 찾지 못했습니다.")
        return false
    end

    local playerName = playerState.PlayerNamePrivate:ToString()
    local palName = getPalName(selected.handle)
    local slotKey = makePalDropSlotKey(playerUid, selected.index)
    pendingPalDropSlots[slotKey] = true

    -- 게임의 기본 팰 드롭 RPC를 사용합니다. 직접 저장 데이터를 지우지 않습니다.
    -- 1초 뒤 슬롯이 실제로 비워졌는지 검사하고, 그대로면 최대 두 번 더 재시도합니다.
    local attempts = 0
    local function requestAndVerify()
        attempts = attempts + 1
        local dropOk, dropErr = pcall(function()
            networkPlayer:RequestDropOtomoPal_ToServer(selected.index)
        end)
        if not dropOk then
            pendingPalDropSlots[slotKey] = nil
            log("팰 드롭 요청에 실패했습니다: " .. tostring(dropErr))
            if onComplete ~= nil then
                onComplete(false, playerName, palName)
            end
            return
        end

        ExecuteWithDelay(1000, function()
            if not isSelectedHandleStillInSlot(holder, selected.index, selected.handle) then
                pendingPalDropSlots[slotKey] = nil
                log(string.format("팰 드롭 완료 확인: %s / 슬롯 %d / %s", playerName, selected.index + 1, palName))
                if onComplete ~= nil then
                    onComplete(true, playerName, palName)
                end
            elseif attempts < 3 then
                log(string.format("팰 드롭 슬롯이 아직 남아 있어 재시도합니다: %s / 슬롯 %d", playerName, selected.index + 1))
                requestAndVerify()
            else
                pendingPalDropSlots[slotKey] = nil
                log(string.format("팰 드롭 실패: 세 번 요청했지만 슬롯이 비워지지 않았습니다: %s / 슬롯 %d", playerName, selected.index + 1))
                if onComplete ~= nil then
                    onComplete(false, playerName, palName)
                end
            end
        end)
    end

    requestAndVerify()
    log(string.format("팰 드롭 요청 시작: %s / 슬롯 %d / %s", playerName, selected.index + 1, palName))
    return true
end

-- 1천원: 플레이어를 현재 위치에서 하늘 위로 텔레포트합니다.
function teleportPlayerSkyward(playerUid)
    local playerState, playerController = findPlayerStateByUid(playerUid)
    if playerState == nil or playerController == nil then
        return nil
    end

    local pawn = playerController.Pawn
    if pawn == nil or not pawn:IsValid() then
        return nil
    end

    local targetLocation = pawn:K2_GetActorLocation()
    local heightOk, heightErr = pcall(function()
        targetLocation.Z = targetLocation.Z + DonationConfig.skyTeleport.height
    end)
    if not heightOk then
        log("하늘 텔레포트 위치 계산에 실패했습니다: " .. tostring(heightErr))
        return nil
    end

    -- 속도/점프가 아닌 좌표를 직접 바꾸는 텔레포트입니다.
    -- 마지막 true는 물리 이동으로 보간하지 않고 즉시 위치를 변경하라는 플래그입니다.
    local moved, resultOrErr = pcall(function()
        return pawn:K2_SetActorLocation(targetLocation, false, {}, true)
    end)
    if not moved then
        log("하늘 텔레포트 처리에 실패했습니다: " .. tostring(resultOrErr))
        return nil
    end

    pcall(function()
        pawn:ForceNetUpdate()
    end)

    local playerName = playerState.PlayerNamePrivate:ToString()
    log("하늘 텔레포트 처리 완료: " .. playerName)
    return playerName
end

-- 10,000원: 팔월드 기본 파편 수류탄의 폭발 액터를 후원자 위치에 생성합니다.
-- SpawnActor에는 UBlueprint가 아니라 BlueprintGeneratedClass가 필요합니다. 다른
-- UE4SS 모드(BPModLoaderMod)가 쓰는 전체 클래스 이름 형식을 사용하고, 로드한
-- 블루프린트의 GeneratedClass도 보조 경로로 사용합니다.
local fragGrenadeExplosionAssetPath = "/Game/Pal/Blueprint/Weapon/Explosion/BP_Explosion_FragGrenade"
local fragGrenadeExplosionClassPath = fragGrenadeExplosionAssetPath .. ".BP_Explosion_FragGrenade_C"
local fragGrenadeExplosionClassName = "BlueprintGeneratedClass " .. fragGrenadeExplosionClassPath
local fragGrenadeExplosionClass = nil

local function isValidObject(object)
    local validOk, isValid = pcall(function()
        return object ~= nil and object:IsValid()
    end)
    return validOk and isValid
end

local function findFragGrenadeExplosionClass()
    -- UE4SS의 StaticFindObject는 UClass의 전체 이름에 BlueprintGeneratedClass
    -- 접두사가 필요합니다. 접두사 없는 경로는 UClass가 아닌 무효 UObject가 됩니다.
    local objectNames = {
        fragGrenadeExplosionClassName,
        fragGrenadeExplosionClassPath,
    }

    for _, objectName in ipairs(objectNames) do
        local lookupOk, classOrErr = pcall(function()
            return StaticFindObject(objectName)
        end)
        if lookupOk and isValidObject(classOrErr) then
            return classOrErr
        end
    end

    return nil
end

local function getFragGrenadeExplosionClass()
    if isValidObject(fragGrenadeExplosionClass) then
        return fragGrenadeExplosionClass
    end

    local existingClass = findFragGrenadeExplosionClass()
    if existingClass ~= nil then
        fragGrenadeExplosionClass = existingClass
        return fragGrenadeExplosionClass
    end

    local loadOk, loadedAsset, assetFound, assetLoaded = pcall(function()
        return LoadAsset(fragGrenadeExplosionAssetPath)
    end)
    if not loadOk then
        log("수류탄 폭발 에셋을 불러오지 못했습니다: " .. tostring(loadedAsset))
        return nil
    end

    log(string.format("수류탄 폭발 에셋 로드 결과: found=%s, loaded=%s", tostring(assetFound), tostring(assetLoaded)))

    -- LoadAsset은 블루프린트 에셋(UBlueprint)을 반환합니다. 그 안의 GeneratedClass가
    -- SpawnActor가 요구하는 UClass이므로, 바로 사용할 수 있으면 우선 사용합니다.
    if isValidObject(loadedAsset) then
        local generatedClassOk, generatedClassOrErr = pcall(function()
            return loadedAsset.GeneratedClass
        end)
        if generatedClassOk and isValidObject(generatedClassOrErr) then
            fragGrenadeExplosionClass = generatedClassOrErr
            return fragGrenadeExplosionClass
        end
        if not generatedClassOk then
            log("수류탄 폭발 GeneratedClass를 읽지 못했습니다: " .. tostring(generatedClassOrErr))
        end
    end

    -- 일부 UE4SS/게임 버전에서는 GeneratedClass 프로퍼티가 직접 노출되지 않으므로,
    -- 에셋 로드 후 전체 BlueprintGeneratedClass 이름으로 한 번 더 조회합니다.
    local loadedClass = findFragGrenadeExplosionClass()
    if loadedClass ~= nil then
        fragGrenadeExplosionClass = loadedClass
        return fragGrenadeExplosionClass
    end

    log("수류탄 폭발 클래스를 찾지 못했습니다: " .. fragGrenadeExplosionClassName)
    return nil
end

function explodePlayerAtPosition(playerUid)
    if not ensureGameReferences() then
        log("폭발 처리에 필요한 게임 참조를 찾지 못했습니다.")
        return nil
    end

    local playerState, playerController = findPlayerStateByUid(playerUid)
    if playerState == nil or playerController == nil then
        log("폭발 대상 플레이어를 찾지 못했습니다.")
        return nil
    end

    local pawn = playerController.Pawn
    if pawn == nil or not pawn:IsValid() then
        log("폭발 대상 캐릭터를 찾지 못했습니다.")
        return nil
    end

    local transformOk, locationOrErr, rotation = pcall(function()
        return pawn:K2_GetActorLocation(), pawn:K2_GetActorRotation()
    end)
    if not transformOk then
        log("폭발 위치를 읽지 못했습니다: " .. tostring(locationOrErr))
        return nil
    end

    -- UE4SS의 UWorld:SpawnActor는 FVector/FRotator userdata가 아니라 Lua 테이블을
    -- 받습니다. K2_GetActorLocation/Rotation의 반환값을 명시적으로 변환합니다.
    local vectorOk, spawnLocationOrErr, spawnRotation = pcall(function()
        return {
            X = locationOrErr.X,
            Y = locationOrErr.Y,
            Z = locationOrErr.Z,
        }, {
            Pitch = rotation.Pitch,
            Yaw = rotation.Yaw,
            Roll = rotation.Roll,
        }
    end)
    if not vectorOk then
        log("폭발 좌표를 SpawnActor 형식으로 변환하지 못했습니다: " .. tostring(spawnLocationOrErr))
        return nil
    end

    local explosionClass = getFragGrenadeExplosionClass()
    if explosionClass == nil then
        return nil
    end

    local spawnOk, explosionOrErr = pcall(function()
        return World:SpawnActor(explosionClass, spawnLocationOrErr, spawnRotation)
    end)
    if not spawnOk or explosionOrErr == nil then
        log("수류탄 폭발 생성에 실패했습니다: " .. tostring(explosionOrErr))
        return nil
    end

    local validOk, isValid = pcall(function()
        return explosionOrErr:IsValid()
    end)
    if not validOk or not isValid then
        log("수류탄 폭발 액터가 유효하지 않습니다: " .. tostring(explosionOrErr))
        return nil
    end

    pcall(function()
        explosionOrErr:ForceNetUpdate()
    end)

    local playerName = playerState.PlayerNamePrivate:ToString()
    log("수류탄 폭발 생성 완료: " .. playerName)
    return playerName
end

-- 10,000원: 보상 목록의 일반 아이템 중 대상 인벤토리에 실제로 있는 한 종류를
-- 무작위로 골라 정확히 1개 제거합니다. 돈, 장비, 핵심/팰 아이템은 후보에서 제외해
-- 의도하지 않은 영구 손실을 막습니다.
local function selectRandomOwnedDonationItem(inventory)
    if DonationRewardCatalog == nil or DonationRewardCatalog.consumables == nil then
        return nil, "보상 아이템 목록을 불러오지 못했습니다."
    end

    local candidates = {}
    local seenItemIds = {}
    for _, tier in ipairs(DonationRewardCatalog.consumables) do
        for _, item in ipairs(tier.items) do
            if item.id ~= "Money" and not seenItemIds[item.id] then
                seenItemIds[item.id] = true
                local countOk, countOrErr = pcall(function()
                    return inventory:CountItemNum(FName(item.id))
                end)
                local itemCount = countOk and tonumber(countOrErr) or nil
                if itemCount ~= nil and itemCount >= 1 then
                    table.insert(candidates, {
                        id = item.id,
                        name = item.name,
                        count = itemCount,
                    })
                end
            end
        end
    end

    if #candidates == 0 then
        return nil, "삭제 가능한 일반 아이템이 인벤토리에 없습니다."
    end
    return candidates[math.random(1, #candidates)], nil
end

-- AddItem_ServerInternal only adds items in the installed game build: a
-- negative Count is accepted but ignored.  Locate the actual replicated item
-- slot instead and change its StackCount on the authoritative server.
local function findItemSlotForStaticId(inventory, staticItemId)
    local containerOut = {}
    local foundOk, foundOrErr = pcall(function()
        return inventory:TryGetContainerFromStaticItemID(FName(staticItemId), containerOut)
    end)
    if not foundOk then
        return nil, "container lookup failed: " .. tostring(foundOrErr)
    end

    local container = containerOut.OutContainer
    if not foundOrErr or container == nil or not container:IsValid() then
        return nil, "item container was not returned"
    end

    local sizeOk, sizeOrErr = pcall(function()
        return container:Num()
    end)
    local slotCount = sizeOk and tonumber(sizeOrErr) or nil
    if slotCount == nil then
        return nil, "container size read failed: " .. tostring(sizeOrErr)
    end

    for index = 0, slotCount - 1 do
        local slotOk, slotOrErr = pcall(function()
            return container:Get(index)
        end)
        local slot = slotOk and slotOrErr or nil
        if slot ~= nil and slot:IsValid() then
            local idOk, idOrErr = pcall(function()
                return slot.ItemId.StaticId:ToString()
            end)
            if idOk and idOrErr == staticItemId then
                return slot, nil
            end
        end
    end

    return nil, "matching item slot was not found"
end

function removeRandomInventoryItem(playerUid, onComplete)
    if not ensureGameReferences() then
        log("랜덤 아이템 삭제에 필요한 게임 참조를 찾지 못했습니다.")
        return false
    end

    -- 후원 채팅 훅과 같은 틱에서 인벤토리를 변경하면 호출이 거부될 수 있으므로,
    -- 기존 아이템 지급과 동일하게 다음 게임 틱에 처리합니다.
    ExecuteWithDelay(0, function()
        local playerState = findPlayerStateByUid(playerUid)
        if playerState == nil or not playerState:IsValid() then
            if onComplete ~= nil then
                onComplete(false, nil, nil, "대상 플레이어를 찾지 못했습니다.")
            end
            return
        end

        local playerName = playerState.PlayerNamePrivate:ToString()
        local inventoryOk, inventoryOrErr = pcall(function()
            return playerState:GetInventoryData()
        end)
        if not inventoryOk or inventoryOrErr == nil or not inventoryOrErr:IsValid() then
            log("랜덤 아이템 삭제에 필요한 인벤토리를 찾지 못했습니다: " .. tostring(inventoryOrErr))
            if onComplete ~= nil then
                onComplete(false, playerName, nil, "인벤토리에 접근할 수 없습니다.")
            end
            return
        end

        local selectedItem, selectionErr = selectRandomOwnedDonationItem(inventoryOrErr)
        if selectedItem == nil then
            log("랜덤 아이템 삭제 대상 선택에 실패했습니다: " .. tostring(selectionErr))
            if onComplete ~= nil then
                onComplete(false, playerName, nil, selectionErr)
            end
            return
        end

        -- AddItem_ServerInternal의 음수 Count는 현재 게임 버전에서 삭제로 처리되지
        -- 않으므로, 실제 아이템 슬롯의 수량을 서버에서 1 줄입니다.
        local itemSlot, slotErr = findItemSlotForStaticId(inventoryOrErr, selectedItem.id)
        if itemSlot == nil then
            log("random item deletion slot lookup failed (" .. selectedItem.id .. "): " .. tostring(slotErr))
            if onComplete ~= nil then
                onComplete(false, playerName, selectedItem.name, "item slot lookup failed")
            end
            return
        end

        -- Item slots are replicated server-owned objects.  Changing the slot
        -- count here is the deletion path; do not use AddItem with -1.
        local removalOk, removalResultOrErr = pcall(function()
            local slotCount = tonumber(itemSlot.StackCount)
            if slotCount == nil or slotCount < 1 then
                error("invalid slot count: " .. tostring(itemSlot.StackCount))
            end
            itemSlot.StackCount = slotCount - 1
            return slotCount
        end)
        if not removalOk then
            log("랜덤 아이템 삭제 호출에 실패했습니다 (" .. selectedItem.id .. "): " .. tostring(removalResultOrErr))
            if onComplete ~= nil then
                onComplete(false, playerName, selectedItem.name, "아이템 차감 호출에 실패했습니다.")
            end
            return
        end

        ExecuteWithDelay(0, function()
            local verifyOk, remainingOrErr = pcall(function()
                return inventoryOrErr:CountItemNum(FName(selectedItem.id))
            end)
            local remainingCount = verifyOk and tonumber(remainingOrErr) or nil
            if remainingCount == selectedItem.count - 1 then
                log(string.format("랜덤 아이템 삭제 완료: %s / %s x1", playerName, selectedItem.id))
                if onComplete ~= nil then
                    onComplete(true, playerName, selectedItem.name, nil)
                end
            else
                log(string.format("랜덤 아이템 삭제 확인 실패: %s / %s (전=%d, 후=%s, 호출결과=%s)", playerName, selectedItem.id, selectedItem.count, tostring(remainingCount), tostring(removalResultOrErr)))
                if onComplete ~= nil then
                    onComplete(false, playerName, selectedItem.name, "수량이 1개 감소했는지 확인하지 못했습니다.")
                end
            end
        end)
    end)
    return true
end

function handleDonationRule(playerUid, amount)
    log(string.format("후원 보상 규칙 처리 시작: UID.A=%d, 금액=%d", playerUid.A, amount))
    local targetName = findPlayerName(playerUid)

    if amount == DonationConfig.amounts.skyTeleport then
        local teleportedName = teleportPlayerSkyward(playerUid)
        if teleportedName ~= nil then
            ModActor:Broadcast(string.format("[후원] [%s]님이 1,000원 후원으로 하늘 위로 텔레포트됩니다!", teleportedName))
        else
            log("하늘 텔레포트 처리에 실패했습니다: UID.A=" .. tostring(playerUid.A))
        end

    elseif amount == DonationConfig.amounts.dropPal then
        local dropQueued = dropRandomPartyPal(playerUid, function(succeeded, targetPlayerName, palName)
            if succeeded then
                ModActor:Broadcast(string.format("[후원] [%s]님의 팰 [%s]이(가) 바닥에 떨어졌습니다!", targetPlayerName, palName))
            else
                ModActor:Broadcast(string.format("[후원] [%s]님의 팰 드롭에 실패했습니다.", targetPlayerName))
            end
        end)
        if not dropQueued then
            log("팰 드롭 처리에 실패했습니다: UID.A=" .. tostring(playerUid.A))
        end

    elseif amount == DonationConfig.amounts.randomItemRemoval then
        local removalQueued = removeRandomInventoryItem(playerUid, function(removed, removedPlayerName, removedItemName, removalErr)
            local displayName = removedPlayerName or targetName
            if removed then
                ModActor:Broadcast(string.format("[후원] [%s]님의 인벤토리에서 랜덤 아이템 [%s] 1개가 삭제되었습니다!", displayName, removedItemName))
            else
                ModActor:Broadcast(string.format("[후원] [%s]님의 10,000원 랜덤 아이템 삭제에 실패했습니다. 서버 로그를 확인하세요.", displayName))
                log("랜덤 아이템 삭제에 실패했습니다: UID.A=" .. tostring(playerUid.A) .. ", 이유=" .. tostring(removalErr))
            end
        end)
        if not removalQueued then
            ModActor:Broadcast(string.format("[후원] [%s]님의 10,000원 랜덤 아이템 삭제에 실패했습니다. 서버 로그를 확인하세요.", targetName))
        end

    elseif amount == DonationConfig.amounts.consumableRoulette then
        local item, grade = selectDonationConsumable()
        log(string.format("소모품 룰렛 결과: %s (%s) x%d", item.name, grade, item.count))

        if not DonationConfig.enableItemDelivery then
            ModActor:Broadcast(string.format("[후원] [%s]님의 7,000원 랜덤 아이템 결과: %s 등급 [%s %d개]", targetName, grade, item.name, item.count))
            log("아이템 지급 비활성화 상태: 룰렛 결과만 안내했습니다.")
            return
        end

        queueItemDelivery(playerUid, item.id, item.count, function(delivered)
            if delivered then
                ModActor:Broadcast(string.format("[후원] [%s]님이 7,000원 랜덤 아이템에서 %s 등급 [%s %d개]를 획득했습니다!", targetName, grade, item.name, item.count))
            else
                ModActor:Broadcast(string.format("[후원] [%s]님의 랜덤 아이템 지급에 실패했습니다. 서버 로그를 확인하세요.", targetName))
                log("소모품 룰렛 지급에 실패했습니다. 인게임 오류 안내를 보냈습니다.")
            end
        end)
    else
        log("설정하지 않은 후원 금액입니다: " .. tostring(amount))
    end
end
