ModMaterialsFileAdd("mods/floor_is_lava/files/materials.xml")
dofile_once("mods/floor_is_lava/files/logic.lua")
dofile_once("mods/floor_is_lava/files/start_room.lua")
dofile_once("mods/floor_is_lava/files/messages.lua")

FloorIsLavaCarveStartRoom()

local start

function OnWorldInitialized()
    for _, tag in ipairs({"floor_is_lava_sample", "floor_is_lava_message"}) do
        for _, entity in ipairs(EntityGetWithTag(tag) or {}) do EntityKill(entity) end
    end
end

function OnPlayerSpawned(player)
    FloorIsLavaStartRun()
    if not GameHasFlagRun("floor_is_lava_spawned") and not start then
        start = { player = player, frame = GameGetFrameNum() }
    end
end

function OnWorldPostUpdate()
    local frame = GameGetFrameNum()
    if start and not start.greeted and frame >= start.frame + 2 then
        FloorIsLavaShowMessage(start.player, {"Find something to stand on!"})
        start.greeted = true
    end
    -- Give the start area time to load before dropping the items in.
    if start and frame >= start.frame + 25 then
        FloorIsLavaPlaceStartItems()
        GameAddFlagRun("floor_is_lava_spawned")
        start = nil
    end
    local players = EntityGetWithTag("player_unit") or {}
    for _, player in ipairs(players) do FloorIsLavaUpdate(player) end
    -- After the update, so a reloaded save has its grace timer carried over.
    if not GameHasFlagRun("floor_is_lava_warned") then
        local left = FloorIsLavaGraceLeft()
        if left > 0 and left <= 120 then
            for _, player in ipairs(players) do
                FloorIsLavaShowMessage(player, {"Here we go!", "The floor is lava!"})
            end
            GameAddFlagRun("floor_is_lava_warned")
        end
    end
    FloorIsLavaUpdateMessages()
    FloorIsLavaDrawStatus()
end
