-- A cave in the rock above the mine entrance, with a shaft down into the
-- tunnel and two potion altars holding the tablet and a water potion.
--
-- The game builds the start area from left_entrance.png at world (0, -512)
-- when the world is generated. The cave and altars are painted into that
-- image (and its colour overlay) during mod init, so they get the same edge
-- textures as the rest of the start area.
local scene = "data/biome_impl/mountain/left_entrance.png"
local visual = "data/biome_impl/mountain/left_entrance_visual.png"

-- Air in the scene image, as "row:first-last,first-last;..." pixel runs.
local cave =
    "288:425-476;289:416-480;290:410-484;291:406-486;292:402-488;293:400-489;294:397-490;" ..
    "295:395-490;296:393-491;297:392-491;298:391-492;299:390-493;300:389-493;301:388-493;" ..
    "302:388-494;303:387-494;304:386-494;305:385-494;306:384-494;307:384-494;308:383-494;" ..
    "309:383-494;310:383-494;311:383-494;312:383-494;313:382-493;314:382-493;315:382-493;" ..
    "316:382-493;317:382-492;318:382-492;319:382-492;320:382-492;321:382-491;322:382-491;" ..
    "323:382-490;324:382-490;325:382-489;326:382-489;327:382-488;328:383-487;329:383-487;" ..
    "330:384-486;331:384-486;332:385-485;333:386-485;334:387-485;335:388-402,404-425,427-484;" ..
    "336:390-393,405-416,428-484;337:432-484;338:442-483;339:446-483;340:450-483;341:452-483;" ..
    "342:453-482;343:454-482;344:454-482;345:455-482;346:455-482;347:455-482;348:456-482;" ..
    "349:456-482;350:456-482;351:456-483;352:455-483;353:455-483;354:455-483;355:455-483;" ..
    "356:456-483;357:456-483;358:457-483;359:458-483;360:458-483;361:459-482;362:459-482;" ..
    "363:460-481;364:461-480"

-- The game's potion altar (data/biome_impl/potion_altar.png and its _visual),
-- cropped to the altar. b = brickwork, g = glowing symbol, . = leave as is.
local altar_material = {
    "bbbbbbbbbb", "bbbbbbbbbb", "bbbbbbbbbb", "bbbgggbbbb", "bbbbbgbbbb",
    "bbbbgbbbbb", "bbbgbbgbbb", "bbbbbbbbbb", "bbbggggbbb", "bbbbbbbbbb",
    ".b.bbbbb..", "...b.b.b..", "...b.b.b..",
}
local altar_colors = {
    "1121111212", "2222222222", "3333333333", "3114551113", "2111151662",
    "2111511112", "3114115663", "2662112112", "3114554113", "2662112112",
    "11131131..", "...21121..", "...11111..",
}
local materials = { b = 0x786c42, g = 0xa3f06e }
local palette = {
    ["1"] = 0x514a31, ["2"] = 0x403a29, ["3"] = 0x302c29,
    ["4"] = 0x71de69, ["5"] = 0x98f491, ["6"] = 0x605739,
}
-- Top-left corner of each altar in world coordinates; items sit 4 px above.
local altars = { { 394, -189 }, { 417, -189 } }

local items = {
    { "mods/floor_is_lava/files/tablet.xml", 399, -193 },
    { "data/entities/items/pickup/potion_water.xml", 422, -193 },
}

-- Must run during mod init, before the start area is generated.
function FloorIsLavaCarveStartRoom()
    local id, w, h = ModImageMakeEditable(scene, 0, 0)
    if id == 0 or w < 512 or h < 512 then return end
    -- The spawn point is known air. Its value also tells us the channel
    -- order: ABGR as documented, or ARGB if the game swapped red and blue.
    local air = ModImageGetPixel(id, 227, 433)
    local abgr = air ~= 0xff000042
    local function color(rgb)
        if abgr then
            local r, g, b = math.floor(rgb / 65536), math.floor(rgb / 256) % 256, rgb % 256
            rgb = b * 65536 + g * 256 + r
        end
        return 0xff000000 + rgb
    end
    for y, runs in cave:gmatch("(%d+):([%d%-,]+)") do
        for first, last in runs:gmatch("(%d+)%-(%d+)") do
            for x = tonumber(first), tonumber(last) do ModImageSetPixel(id, x, tonumber(y), air) end
        end
    end
    local overlay = ModImageMakeEditable(visual, 0, 0)
    for _, altar in ipairs(altars) do
        for row = 1, #altar_material do
            local y = altar[2] + row - 1 + 512
            for col = 1, 10 do
                local x = altar[1] + col - 1
                local m = materials[altar_material[row]:sub(col, col)]
                if m then
                    ModImageSetPixel(id, x, y, color(m))
                    local c = palette[altar_colors[row]:sub(col, col)]
                    if overlay ~= 0 then ModImageSetPixel(overlay, x, y, c and color(c) or 0) end
                end
            end
        end
    end
end

function FloorIsLavaPlaceStartItems()
    for _, item in ipairs(items) do EntityLoad(item[1], item[2], item[3]) end
end
