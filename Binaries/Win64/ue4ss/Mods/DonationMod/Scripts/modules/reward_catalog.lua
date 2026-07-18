-- 참고 목록: Scripts/enums/itemdata.lua (Palworld Dataminer 생성 목록)
-- 보상 목록만 이 파일에서 관리합니다. 항목의 id는 게임 내부 StaticItemId입니다.

DonationRewardCatalog = {
    consumables = {
        {
            maxRoll = 5,
            grade = "전설 (5%)",
            items = {
                { id = "PalSphere_Exotic", count = 3, name = "엑조틱 스피어" },
                { id = "PalSphere_Ultimate", count = 5, name = "울티메이트 스피어" },
                { id = "PalSphere_Ancient_2", count = 3, name = "고대 스피어" },
                { id = "Diamond", count = 3, name = "다이아몬드" },
                { id = "PalUpgradeStone4", count = 2, name = "거대 팰 영혼" },
                { id = "PalRevive", count = 2, name = "부활 물약" },
                { id = "Elixir_hp_Yakushima", count = 1, name = "생명 크리스탈" },
                { id = "AncientParts3", count = 2, name = "고대 팰 원고" }
            }
        },
        {
            maxRoll = 30,
            grade = "레어 (25%)",
            items = {
                { id = "PalSphere_Legend", count = 5, name = "레전더리 스피어" },
                { id = "PalSphere_Master", count = 10, name = "울트라 스피어" },
                { id = "PalSphere_Tera", count = 15, name = "하이퍼 스피어" },
                { id = "PalUpgradeStone3", count = 3, name = "대형 팰 영혼" },
                { id = "AncientParts2", count = 3, name = "고대 문명 코어" },
                { id = "PalOil", count = 15, name = "고급 팰 기름" },
                { id = "CrudeOil", count = 20, name = "원유" },
                { id = "ManganeseOre", count = 20, name = "코랄리움 광석" },
                { id = "Thermal_Core", count = 3, name = "열 코어" }
            }
        },
        {
            maxRoll = 100,
            grade = "일반 (70%)",
            items = {
                { id = "Money", count = 1000, name = "골드 코인" },
                { id = "PalSphere", count = 20, name = "팰 스피어" },
                { id = "PalSphere_Mega", count = 15, name = "메가 스피어" },
                { id = "PalSphere_Giga", count = 10, name = "기가 스피어" },
                { id = "Baked_Berries", count = 30, name = "구운 열매" },
                { id = "Pan", count = 20, name = "빵" },
                { id = "PalFluid", count = 15, name = "팰의 체액" },
                { id = "Leather", count = 30, name = "가죽" },
                { id = "Bone", count = 30, name = "뼈" },
                { id = "CopperOre", count = 50, name = "광석" },
                { id = "Stone", count = 100, name = "돌" },
                { id = "Wood", count = 100, name = "나무" },
                { id = "Coal", count = 50, name = "석탄" },
                { id = "Quartz", count = 50, name = "순수 석영" },
                { id = "FireOrgan", count = 20, name = "발화 기관" },
                { id = "ElectricOrgan", count = 20, name = "전기 기관" },
                { id = "IceOrgan", count = 20, name = "빙결 기관" },
                { id = "Venom", count = 20, name = "독샘" }
            }
        }
    }
}

function selectDonationConsumable()
    local roll = math.random(1, 100)

    for _, tier in ipairs(DonationRewardCatalog.consumables) do
        if roll <= tier.maxRoll then
            local item = tier.items[math.random(1, #tier.items)]
            return item, tier.grade
        end
    end

    error("후원 아이템 룰렛 목록을 선택하지 못했습니다.")
end
