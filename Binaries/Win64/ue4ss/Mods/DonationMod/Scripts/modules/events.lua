-- Compatibility module
--
-- The original mod used an old EnterChat_Receive hook and executed startup
-- diagnostics against native inventory functions.  Neither is required for
-- donations, and both can run while a player is loading into the server.
-- The supported chat command hook lives only in modules/commands.lua.

log("[후원] 구형 이벤트 훅과 시작 진단을 비활성화했습니다.")

-- Log the reflected signature once after the world has started.  This is
-- diagnostic only: it never calls the inventory function or edits inventory.
local function inspectAddItemSignature()
    local lookupOk, addItemFunction = pcall(function()
        return StaticFindObject("/Script/Pal.PalPlayerInventoryData:AddItem_ServerInternal")
    end)
    if not lookupOk or addItemFunction == nil then
        log("[후원] AddItem_ServerInternal 함수를 찾지 못했습니다: " .. tostring(addItemFunction))
        return
    end

    local headerOk, headerErr = pcall(function()
        log("[후원] AddItem_ServerInternal 함수 정보: NumParms=" .. tostring(addItemFunction.NumParms)
            .. ", ParmsSize=" .. tostring(addItemFunction.ParmsSize))
    end)
    if not headerOk then
        log("[후원] AddItem 함수 기본 정보 읽기에 실패했습니다: " .. tostring(headerErr))
    end

    local propertyCount = 0
    local propertiesOk, propertiesErr = pcall(function()
        addItemFunction:ForEachProperty(function(property)
            propertyCount = propertyCount + 1

            -- Some reflected properties do not expose every helper method in
            -- this UE4SS build.  Keep inspecting the remaining properties
            -- instead of aborting the entire signature dump on one entry.
            local detailOk, detailOrErr = pcall(function()
                local propertyName = property:GetFName():ToString()
                local propertyClass = property:GetClass():GetFName():ToString()
                local offset = property:GetOffset_Internal()
                return propertyName .. " (" .. propertyClass .. ", offset=" .. tostring(offset) .. ")"
            end)

            if detailOk then
                log("[후원] AddItem 인자 " .. tostring(propertyCount) .. ": " .. detailOrErr)
            else
                log("[후원] AddItem 인자 " .. tostring(propertyCount) .. " 정보를 읽지 못했습니다: " .. tostring(detailOrErr))
            end
        end)
    end)
    if not propertiesOk then
        log("[후원] AddItem 인자 목록 읽기에 실패했습니다: " .. tostring(propertiesErr))
    elseif propertyCount == 0 then
        log("[후원] AddItem 인자 목록이 비어 있습니다.")
    end
end

-- The game update that is currently installed ignores a negative Count passed
-- to AddItem_ServerInternal.  Before selecting the real consume API, dump the
-- exact runtime signatures.  Names and parameters change between Palworld
-- updates, so this prevents a guessed call from touching the wrong slot.
local function inspectFunctionSignature(label, objectPath)
    local lookupOk, reflectedFunction = pcall(function()
        return StaticFindObject(objectPath)
    end)
    if not lookupOk or reflectedFunction == nil then
        log("[Donation] " .. label .. " not found: " .. tostring(reflectedFunction))
        return
    end

    local headerOk, headerErr = pcall(function()
        log("[Donation] " .. label .. " signature: NumParms=" .. tostring(reflectedFunction.NumParms)
            .. ", ParmsSize=" .. tostring(reflectedFunction.ParmsSize))
    end)
    if not headerOk then
        log("[Donation] " .. label .. " header read failed: " .. tostring(headerErr))
    end

    local propertyCount = 0
    local propertiesOk, propertiesErr = pcall(function()
        reflectedFunction:ForEachProperty(function(property)
            propertyCount = propertyCount + 1
            local detailOk, detailOrErr = pcall(function()
                local propertyName = property:GetFName():ToString()
                local propertyClass = property:GetClass():GetFName():ToString()
                local offset = property:GetOffset_Internal()
                return propertyName .. " (" .. propertyClass .. ", offset=" .. tostring(offset) .. ")"
            end)

            if detailOk then
                log("[Donation] " .. label .. " parameter " .. tostring(propertyCount) .. ": " .. detailOrErr)
            else
                log("[Donation] " .. label .. " parameter " .. tostring(propertyCount) .. " read failed: " .. tostring(detailOrErr))
            end
        end)
    end)
    if not propertiesOk then
        log("[Donation] " .. label .. " parameter enumeration failed: " .. tostring(propertiesErr))
    elseif propertyCount == 0 then
        log("[Donation] " .. label .. " has no reflected parameters")
    end
end

local function inspectDeletionApiSignatures()
    inspectAddItemSignature()
    inspectFunctionSignature(
        "RequestConsumeItemsByPlayerControllableItems_ServerInternal",
        "/Script/Pal.PalItemUtility:RequestConsumeItemsByPlayerControllableItems_ServerInternal"
    )
    inspectFunctionSignature(
        "UpdateItem_ServerInternal",
        "/Script/Pal.PalItemSlot:UpdateItem_ServerInternal"
    )
    inspectFunctionSignature(
        "TryGetContainerFromStaticItemID",
        "/Script/Pal.PalPlayerInventoryData:TryGetContainerFromStaticItemID"
    )
    inspectFunctionSignature(
        "PalItemContainer:Get",
        "/Script/Pal.PalItemContainer:Get"
    )
end

if type(ExecuteInGameThreadWithDelay) == "function" then
    ExecuteInGameThreadWithDelay(3000, inspectDeletionApiSignatures)
else
    ExecuteInGameThread(function()
        inspectDeletionApiSignatures()
    end)
end
