DonationConfig = {
    -- false면 아이템을 인벤토리에 지급하지 않고 룰렛 결과만 채팅에 표시합니다.
    enableItemDelivery = true,
    paths = {
        donationQueue = DonationScriptDirectory .. "\\donations.queue",
        playerStatus = DonationScriptDirectory .. "\\players.status",
        streamerRegistrationRequest = DonationScriptDirectory .. "\\streamer-registration.requests",
        streamerRegistrationResponse = DonationScriptDirectory .. "\\streamer-registration.responses",
        bindingDumpRequest = DonationScriptDirectory .. "\\dump-bindings.request",
    },
    amounts = {
        skyTeleport = 1000,
        dropPal = 5000,
        consumableRoulette = 7000,
        randomItemRemoval = 10000,
    },
    skyTeleport = {
        -- Unreal Engine 좌표 기준으로 위로 이동할 거리입니다.
        height = 20000.0,
    },
}
