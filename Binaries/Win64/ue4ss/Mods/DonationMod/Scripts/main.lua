local scriptSource = debug.getinfo(1, "S").source or ""
local scriptPath = scriptSource:sub(1, 1) == "@" and scriptSource:sub(2) or scriptSource
local scriptDirectory = scriptPath:match("^(.*)[/\\]") or "."

DonationScriptDirectory = scriptDirectory

local function loadDonationModule(name)
    local path = scriptDirectory .. "\\modules\\" .. name .. ".lua"
    local chunk, err = loadfile(path)
    if chunk == nil then
        error("DonationMod 모듈을 불러올 수 없습니다 ('" .. name .. "'): " .. tostring(err))
    end
    return chunk()
end

loadDonationModule("config")
loadDonationModule("runtime")
loadDonationModule("rewards")
loadDonationModule("reward_catalog")
loadDonationModule("commands")
loadDonationModule("donation_queue")
loadDonationModule("events")
